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

    public TerritoryService(AppDbContext db, IHexGridService hexGrid, IGeoService geo, ITerritoryNotifier notifier)
    {
        _db = db;
        _hexGrid = hexGrid;
        _geo = geo;
        _notifier = notifier;
    }

    public async Task<ClaimResult> ProcessClaim(Guid userId, double[][] path)
    {
        var validationError = await ValidateClaim(userId, path);
        if (validationError != null)
            return ClaimResult.Failure(validationError);

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
                t.CooldownExpiresAt
            })
            .ToListAsync();

        return filtered.Select(t => new TerritoryCellResponse
        {
            CellId = t.CellId,
            Boundary = JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
            OwnerId = t.OwnerId,
            OwnerColor = t.OwnerColor,
            OwnerName = t.OwnerName,
            CooldownExpiresAtUtc = t.CooldownExpiresAt,
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
                t.CooldownExpiresAt
            })
            .ToListAsync();

        return cells.Select(t => new TerritoryCellResponse
        {
            CellId = t.CellId,
            Boundary = JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
            OwnerId = t.OwnerId,
            OwnerColor = t.OwnerColor,
            OwnerName = t.OwnerName,
            CooldownExpiresAtUtc = t.CooldownExpiresAt,
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
}
