using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

public class TerritoryService : ITerritoryService
{
    private readonly AppDbContext _db;
    private readonly IHexGridService _hexGrid;
    private readonly IGeoService _geo;
    private readonly ITerritoryNotifier _notifier;
    private readonly IPathValidationService _pathValidator;
    private readonly IPushNotificationService _pushService;

    public TerritoryService(AppDbContext db, IHexGridService hexGrid, IGeoService geo,
        ITerritoryNotifier notifier, IPathValidationService pathValidator,
        IPushNotificationService pushService)
    {
        _db = db;
        _hexGrid = hexGrid;
        _geo = geo;
        _notifier = notifier;
        _pathValidator = pathValidator;
        _pushService = pushService;
    }

    public async Task<ClaimResult> ProcessClaim(Guid userId, double[][] path)
    {
        var validationError = await ValidateClaim(userId, path);
        if (validationError != null)
            return ClaimResult.Failure(validationError);

        var pathError = _pathValidator.Validate(path);
        if (pathError != null)
            return ClaimResult.Failure(pathError);

        var cells = _hexGrid.ComputeCapturedCells(path);
        if (cells.Count == 0)
            return ClaimResult.Failure("No hexes captured — walk a closed loop to claim territory");

        if (!_hexGrid.HasClosedLoop(path))
            return ClaimResult.Failure("No closed loop detected — walk back near your starting point");

        var area = _hexGrid.CalculateArea(cells.Count);
        if (area > GameConstants.MaxClaimAreaSquareMeters)
            return ClaimResult.Failure("Claim too large — max 5km² per claim");

        await using var transaction = await _db.Database.BeginTransactionAsync();
        try
        {
            var claim = CreateClaimEntity(userId, cells.Count, area, path);
            var (boundaries, transfers) = await AssignCells(userId, cells, claim.Id);

            _db.CellTransfers.AddRange(transfers);
            _db.Claims.Add(claim);

            var totalDistance = _geo.CalculatePathDistance(path);
            await UpdateUserStats(userId, transfers, totalDistance);
            await _db.SaveChangesAsync();
            await transaction.CommitAsync();

            await BroadcastOwnershipChanges(userId, cells, transfers);
            await NotifyVictimsOfTheft(userId, transfers);

            return ClaimResult.Succeeded(new ClaimResponse
            {
                Id = claim.Id,
                CellCount = claim.CellCount,
                AreaM2 = claim.AreaM2,
                StolenFromOthers = transfers.Count(t => t.FromUserId != null),
                Boundaries = boundaries,
            });
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    public async Task<TrailClaimResult> ProcessTrailClaim(Guid userId, double[][] points)
    {
        if (points.Length == 0)
            return TrailClaimResult.Failure("No GPS points provided");

        if (points.Length > 200)
            return TrailClaimResult.Failure("Too many points in a single batch");

        var cells = _hexGrid.GetTrailCells(points);
        if (cells.Count == 0)
            return TrailClaimResult.Failure("No hexes in batch");

        var cooldownExpiry = DateTime.UtcNow.AddHours(GameConstants.CellCooldownHours);
        var cellIds = cells.Select(c => c.CellId).ToList();

        var existingCells = await _db.TerritoryCells
            .Include(t => t.Owner)
            .Where(t => cellIds.Contains(t.CellId))
            .ToDictionaryAsync(t => t.CellId);

        var claimed = new List<TrailHexResponse>();
        var transfers = new List<CellTransfer>();
        var claimId = Guid.NewGuid();

        foreach (var hexCell in cells)
        {
            if (existingCells.TryGetValue(hexCell.CellId, out var existing))
            {
                if (existing.OwnerId == userId) continue; // already ours
                if (IsOnCooldown(existing)) continue;

                var prevOwnerName = existing.Owner?.DisplayName;
                transfers.Add(CreateTransfer(hexCell.CellId, existing.OwnerId, userId, claimId));
                UpdateExistingCell(existing, userId, claimId, hexCell, cooldownExpiry);
                claimed.Add(new TrailHexResponse
                {
                    CellId = hexCell.CellId,
                    Boundary = hexCell.Boundary,
                    WasStolen = true,
                    PreviousOwnerName = prevOwnerName,
                });
            }
            else
            {
                var newCell = CreateNewCell(userId, claimId, hexCell, cooldownExpiry);
                _db.TerritoryCells.Add(newCell);
                transfers.Add(CreateTransfer(hexCell.CellId, null, userId, claimId));
                claimed.Add(new TrailHexResponse
                {
                    CellId = hexCell.CellId,
                    Boundary = hexCell.Boundary,
                    WasStolen = false,
                });
            }
        }

        if (claimed.Count == 0)
            return TrailClaimResult.Succeeded(new TrailClaimResponse());

        _db.CellTransfers.AddRange(transfers);

        // Update user stats (lightweight — no full claim record)
        var user = await _db.Users.FindAsync(userId);
        if (user != null)
        {
            var newCells = transfers.Count(t => t.FromUserId == null);
            var stolenCells = transfers.Count(t => t.FromUserId != null);
            user.HexCount += newCells + stolenCells;
            user.TotalHexesCaptured += newCells + stolenCells;
            await DecrementVictimHexCounts(userId, transfers);
        }

        await _db.SaveChangesAsync();

        // Broadcast changes for real-time multiplayer
        await BroadcastOwnershipChanges(userId, cells.Where(c =>
            claimed.Any(cl => cl.CellId == c.CellId)).ToList(), transfers);

        var stolenCount = claimed.Count(c => c.WasStolen);
        return TrailClaimResult.Succeeded(new TrailClaimResponse
        {
            ClaimedCells = claimed,
            NewCellCount = claimed.Count,
            StolenCount = stolenCount,
        });
    }

    public async Task<StepClaimResponse> ProcessStepClaim(Guid userId, double lat, double lng)
    {
        var hexCell = _hexGrid.GetCellAtPoint(lat, lng);

        var existing = await _db.TerritoryCells.Include(t => t.Owner)
            .FirstOrDefaultAsync(t => t.CellId == hexCell.CellId);

        // Already ours — refresh decay timer and record exploration, but no new claim
        if (existing != null && existing.OwnerId == userId)
        {
            existing.LastRefreshedAt = DateTime.UtcNow;
            await RecordExploration(userId, hexCell.CellId);
            await _db.SaveChangesAsync();
            return new StepClaimResponse { Claimed = false };
        }

        // On cooldown — can't steal
        if (existing != null && IsOnCooldown(existing))
            return new StepClaimResponse { Claimed = false };

        var cooldownExpiry = DateTime.UtcNow.AddHours(GameConstants.CellCooldownHours);
        var claimId = Guid.NewGuid();
        string? previousOwnerName = null;

        if (existing != null)
        {
            // Steal from another player
            previousOwnerName = existing.Owner?.DisplayName;
            var transfer = CreateTransfer(hexCell.CellId, existing.OwnerId, userId, claimId);
            _db.CellTransfers.Add(transfer);
            UpdateExistingCell(existing, userId, claimId, hexCell, cooldownExpiry);
            await DecrementVictimHexCounts(userId, [transfer]);
        }
        else
        {
            // New cell — claim it
            var newCell = CreateNewCell(userId, claimId, hexCell, cooldownExpiry);
            _db.TerritoryCells.Add(newCell);
            _db.CellTransfers.Add(CreateTransfer(hexCell.CellId, null, userId, claimId));
        }

        // Record exploration (permanent)
        await RecordExploration(userId, hexCell.CellId);

        // Update claimer stats
        var user = await _db.Users.FindAsync(userId);
        if (user != null)
        {
            user.HexCount += 1;
            user.TotalHexesCaptured += 1;
            UpdateStreak(user);
        }

        await _db.SaveChangesAsync();

        // Broadcast for real-time multiplayer (fire-and-forget)
        _ = BroadcastOwnershipChanges(userId, [hexCell],
            [CreateTransfer(hexCell.CellId, existing?.OwnerId, userId, claimId)]);

        return new StepClaimResponse
        {
            Claimed = true,
            CellId = hexCell.CellId,
            Boundary = hexCell.Boundary,
            WasStolen = existing != null,
            PreviousOwnerName = previousOwnerName,
        };
    }

    public async Task<List<TerritoryCellResponse>> GetTerritoriesInViewport(
        double minLat, double minLng, double maxLat, double maxLng)
    {
        var filtered = await _db.TerritoryCells
            .Include(t => t.Owner)
            .Where(t => t.CenterLat >= minLat && t.CenterLat <= maxLat
                     && t.CenterLng >= minLng && t.CenterLng <= maxLng)
            .Take(GameConstants.MaxViewportCells)
            .Select(t => new
            {
                t.CellId, t.BoundaryJson, t.OwnerId,
                OwnerColor = t.Owner!.Color,
                OwnerName = t.Owner!.DisplayName,
                t.CooldownExpiresAt,
                t.ParentCellId,
                t.LastRefreshedAt
            })
            .ToListAsync();

        var decaySeconds = GameConstants.DecayDays * 86400.0;
        return filtered.Select(t => new TerritoryCellResponse
        {
            CellId = t.CellId,
            Boundary = JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
            OwnerId = t.OwnerId,
            OwnerColor = t.OwnerColor,
            OwnerName = t.OwnerName,
            CooldownExpiresAtUtc = t.CooldownExpiresAt,
            ParentCellId = t.ParentCellId,
            DecayProgress = Math.Clamp(
                (DateTime.UtcNow - t.LastRefreshedAt).TotalSeconds / decaySeconds, 0.0, 1.0),
        }).ToList();
    }

    public async Task<TerritoryStatsResponse> GetUserStats(Guid userId)
    {
        var cellCount = await _db.TerritoryCells.CountAsync(t => t.OwnerId == userId);
        return new TerritoryStatsResponse
        {
            CellCount = cellCount,
            AreaM2 = _hexGrid.CalculateArea(cellCount),
        };
    }

    public async Task<StolenCellsResponse> GetStolenCells(Guid userId, int days)
    {
        var clampedDays = Math.Clamp(days, 1, GameConstants.MaxStolenDaysLookback);
        var since = DateTime.UtcNow.AddDays(-clampedDays);

        var stolen = await _db.CellTransfers
            .Where(t => t.FromUserId == userId && t.TransferredAt >= since)
            .OrderByDescending(t => t.TransferredAt)
            .Select(t => new StolenCellDetail
            {
                CellId = t.CellId,
                ToUserId = t.ToUserId,
                TransferredAt = t.TransferredAt,
                ClaimId = t.ClaimId,
            })
            .ToListAsync();

        var byStealer = stolen
            .GroupBy(s => s.ToUserId)
            .Select(g => new StealerSummary { UserId = g.Key, CellsStolen = g.Count() })
            .OrderByDescending(g => g.CellsStolen)
            .ToList();

        return new StolenCellsResponse
        {
            TotalStolen = stolen.Count,
            Since = since,
            ByStealer = byStealer,
            Cells = stolen.Take(GameConstants.MaxStolenCellsResponse).ToList(),
        };
    }

    public async Task<CellHistoryResponse> GetCellHistory(long cellId)
    {
        var history = await _db.CellTransfers
            .Where(t => t.CellId == cellId)
            .OrderByDescending(t => t.TransferredAt)
            .Take(GameConstants.MaxHistoryDepth)
            .Select(t => new CellTransferDetail
            {
                FromUserId = t.FromUserId,
                ToUserId = t.ToUserId,
                TransferredAt = t.TransferredAt,
                ClaimId = t.ClaimId,
            })
            .ToListAsync();

        var currentOwner = await _db.TerritoryCells
            .Where(t => t.CellId == cellId)
            .Select(t => new CellOwnerInfo { OwnerId = t.OwnerId, ClaimedAt = t.ClaimedAt })
            .FirstOrDefaultAsync();

        return new CellHistoryResponse
        {
            CellId = cellId,
            CurrentOwner = currentOwner,
            TransferCount = history.Count,
            History = history,
        };
    }

    public async Task<List<TerritoryCellResponse>> GetUserTerritories(Guid userId)
    {
        var cells = await _db.TerritoryCells
            .Include(t => t.Owner)
            .Where(t => t.OwnerId == userId)
            .OrderByDescending(t => t.ClaimedAt)
            .Take(GameConstants.MaxUserTerritoryCells)
            .Select(t => new
            {
                t.CellId, t.BoundaryJson, t.OwnerId,
                OwnerColor = t.Owner!.Color,
                OwnerName = t.Owner!.DisplayName,
                t.CooldownExpiresAt,
                t.ParentCellId,
                t.LastRefreshedAt
            })
            .ToListAsync();

        var decaySeconds = GameConstants.DecayDays * 86400.0;
        return cells.Select(t => new TerritoryCellResponse
        {
            CellId = t.CellId,
            Boundary = JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
            OwnerId = t.OwnerId,
            OwnerColor = t.OwnerColor,
            OwnerName = t.OwnerName,
            CooldownExpiresAtUtc = t.CooldownExpiresAt,
            ParentCellId = t.ParentCellId,
            DecayProgress = Math.Clamp(
                (DateTime.UtcNow - t.LastRefreshedAt).TotalSeconds / decaySeconds, 0.0, 1.0),
        }).ToList();
    }

    public async Task<List<ClaimHistoryEntry>> GetClaimHistory(Guid userId)
    {
        return await _db.Claims
            .Where(c => c.UserId == userId)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new ClaimHistoryEntry
            {
                ClaimId = c.Id,
                CellCount = c.CellCount,
                AreaM2 = c.AreaM2,
                Date = c.CreatedAt,
            })
            .ToListAsync();
    }

    public async Task<List<ExplorationNeighborhood>> GetExplorationStats(Guid userId, double lat, double lng)
    {
        var neighborhoodIds = _hexGrid.GetNearbyNeighborhoods(lat, lng, k: 1);

        var counts = await _db.ExploredCells
            .Where(e => e.UserId == userId && neighborhoodIds.Contains(e.NeighborhoodId))
            .GroupBy(e => e.NeighborhoodId)
            .Select(g => new { NeighborhoodId = g.Key, Count = g.Count() })
            .ToListAsync();

        var countMap = counts.ToDictionary(c => c.NeighborhoodId, c => c.Count);

        return neighborhoodIds.Select(nId =>
        {
            var center = _hexGrid.GetCellCenter(nId);
            countMap.TryGetValue(nId, out var explored);
            return new ExplorationNeighborhood
            {
                NeighborhoodId = nId,
                CenterLat = center.Lat,
                CenterLng = center.Lng,
                ExploredCount = explored,
                TotalCount = GameConstants.CellsPerNeighborhood,
                Percent = Math.Round(explored * 100.0 / GameConstants.CellsPerNeighborhood, 1),
            };
        }).ToList();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Private helpers — ProcessClaim decomposition
    // ──────────────────────────────────────────────────────────────────────────

    private async Task<string?> ValidateClaim(Guid userId, double[][] path)
    {
        if (path.Length < GameConstants.MinGpsPointsPerClaim)
            return "Path too short — need at least 10 GPS points";

        var totalDistance = _geo.CalculatePathDistance(path);
        if (totalDistance < GameConstants.MinWalkDistanceMeters)
            return "Walk at least 200 meters before claiming";

        var todayStart = DateTime.UtcNow.Date;
        var todayClaimCount = await _db.Claims
            .CountAsync(c => c.UserId == userId && c.CreatedAt >= todayStart);

        if (todayClaimCount >= GameConstants.MaxClaimsPerDay)
            return $"Daily limit reached — max {GameConstants.MaxClaimsPerDay} claims per day";

        return null;
    }

    private static Claim CreateClaimEntity(Guid userId, int cellCount, double area, double[][] path)
    {
        var claim = new Claim
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            CellCount = cellCount,
            AreaM2 = area,
        };
        claim.SetPolygon(path);
        return claim;
    }

    private async Task<(List<double[][]> Boundaries, List<CellTransfer> Transfers)> AssignCells(
        Guid userId, List<HexCell> cells, Guid claimId)
    {
        var transfers = new List<CellTransfer>();
        var boundaries = new List<double[][]>();
        var cooldownExpiry = DateTime.UtcNow.AddHours(GameConstants.CellCooldownHours);

        var cellIds = cells.Select(c => c.CellId).ToList();
        var existingCells = await _db.TerritoryCells
            .Where(t => cellIds.Contains(t.CellId))
            .ToDictionaryAsync(t => t.CellId);

        foreach (var hexCell in cells)
        {
            if (existingCells.TryGetValue(hexCell.CellId, out var existing))
            {
                if (IsOnCooldown(existing)) continue;
                if (existing.OwnerId == userId) continue;
                transfers.Add(CreateTransfer(hexCell.CellId, existing.OwnerId, userId, claimId));
                UpdateExistingCell(existing, userId, claimId, hexCell, cooldownExpiry);
            }
            else
            {
                var newCell = CreateNewCell(userId, claimId, hexCell, cooldownExpiry);
                _db.TerritoryCells.Add(newCell);
                transfers.Add(CreateTransfer(hexCell.CellId, null, userId, claimId));
            }

            boundaries.Add(hexCell.Boundary);
        }

        return (boundaries, transfers);
    }

    private static bool IsOnCooldown(TerritoryCell cell)
    {
        return cell.CooldownExpiresAt.HasValue && cell.CooldownExpiresAt.Value > DateTime.UtcNow;
    }

    private static CellTransfer CreateTransfer(long cellId, Guid? fromUserId, Guid toUserId, Guid claimId)
    {
        return new CellTransfer
        {
            Id = Guid.NewGuid(),
            CellId = cellId,
            FromUserId = fromUserId == toUserId ? null : fromUserId,
            ToUserId = toUserId,
            ClaimId = claimId,
            TransferredAt = DateTime.UtcNow,
        };
    }

    private void UpdateExistingCell(TerritoryCell cell, Guid userId, Guid claimId,
        HexCell hexCell, DateTime cooldownExpiry)
    {
        var center = _hexGrid.GetCellCenter(hexCell.CellId);
        cell.OwnerId = userId;
        cell.ClaimId = claimId;
        cell.ClaimedAt = DateTime.UtcNow;
        cell.LastRefreshedAt = DateTime.UtcNow;
        cell.CooldownExpiresAt = cooldownExpiry;
        cell.CenterLat = center.Lat;
        cell.CenterLng = center.Lng;
        cell.ParentCellId = _hexGrid.GetParentCellId(hexCell.CellId);
        cell.SetBoundary(hexCell.Boundary);
    }

    private TerritoryCell CreateNewCell(Guid userId, Guid claimId, HexCell hexCell, DateTime cooldownExpiry)
    {
        var center = _hexGrid.GetCellCenter(hexCell.CellId);
        var cell = new TerritoryCell
        {
            CellId = hexCell.CellId,
            OwnerId = userId,
            ClaimId = claimId,
            ClaimedAt = DateTime.UtcNow,
            LastRefreshedAt = DateTime.UtcNow,
            CooldownExpiresAt = cooldownExpiry,
            CenterLat = center.Lat,
            CenterLng = center.Lng,
            ParentCellId = _hexGrid.GetParentCellId(hexCell.CellId),
        };
        cell.SetBoundary(hexCell.Boundary);
        return cell;
    }

    private async Task UpdateUserStats(Guid userId, List<CellTransfer> transfers, double totalDistance)
    {
        var user = await _db.Users.FindAsync(userId);
        if (user == null) return;

        var newCells = transfers.Count(t => t.FromUserId == null);
        var stolenCells = transfers.Count(t => t.FromUserId != null);
        user.HexCount += newCells + stolenCells;
        user.TotalHexesCaptured += newCells + stolenCells;
        user.DistanceKm += totalDistance / 1000.0;

        UpdateStreak(user);
        await DecrementVictimHexCounts(userId, transfers);
    }

    private static void UpdateStreak(User user)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        if (user.LastClaimDate == null || user.LastClaimDate < today.AddDays(-1))
            user.Streak = 1;
        else if (user.LastClaimDate == today.AddDays(-1))
            user.Streak += 1;

        user.LastClaimDate = today;
        if (user.Streak > user.MaxStreak)
            user.MaxStreak = user.Streak;
    }

    private async Task RecordExploration(Guid userId, long cellId)
    {
        var exists = await _db.ExploredCells
            .AnyAsync(e => e.UserId == userId && e.CellId == cellId);
        if (exists) return;

        _db.ExploredCells.Add(new Entities.ExploredCell
        {
            UserId = userId,
            CellId = cellId,
            NeighborhoodId = _hexGrid.GetNeighborhoodId(cellId),
            FirstVisitedAt = DateTime.UtcNow,
        });
    }

    private async Task DecrementVictimHexCounts(Guid userId, List<CellTransfer> transfers)
    {
        var stolenGroups = transfers
            .Where(t => t.FromUserId != null && t.FromUserId != userId)
            .GroupBy(t => t.FromUserId!.Value)
            .ToList();

        if (stolenGroups.Count == 0) return;

        var victimIds = stolenGroups.Select(g => g.Key).ToList();
        var victims = await _db.Users
            .Where(u => victimIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id);

        foreach (var group in stolenGroups)
        {
            if (victims.TryGetValue(group.Key, out var victim))
            {
                victim.HexCount = Math.Max(0, victim.HexCount - group.Count());
            }
        }
    }

    private async Task BroadcastOwnershipChanges(
        Guid userId, List<HexCell> cells, List<CellTransfer> transfers)
    {
        var user = await _db.Users.FindAsync(userId);
        if (user == null) return;

        var transferLookup = transfers
            .Where(t => t.FromUserId != null)
            .ToDictionary(t => t.CellId, t => t.FromUserId);

        var changes = cells.Select(c =>
        {
            var center = _hexGrid.GetCellCenter(c.CellId);
            return new HexChangeEvent(
                H3Index: c.CellId.ToString(),
                CenterLat: center.Lat,
                CenterLng: center.Lng,
                NewOwnerId: userId,
                NewOwnerColor: user.Color,
                NewOwnerDisplayName: user.DisplayName,
                PreviousOwnerId: transferLookup.GetValueOrDefault(c.CellId),
                ParentCellId: _hexGrid.GetParentCellId(c.CellId)
            );
        }).ToList();

        await _notifier.NotifyHexOwnershipChanged(changes);
    }

    private async Task NotifyVictimsOfTheft(Guid thiefUserId, List<CellTransfer> transfers)
    {
        var thief = await _db.Users.FindAsync(thiefUserId);
        if (thief == null) return;

        var victimGroups = transfers
            .Where(t => t.FromUserId != null && t.FromUserId != thiefUserId)
            .GroupBy(t => t.FromUserId!.Value);

        foreach (var group in victimGroups)
        {
            await _pushService.NotifyHexStolen(group.Key, thief.DisplayName, group.Count());
        }
    }
}
