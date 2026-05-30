using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MyLoop.Api.Constants;
using MyLoop.Api.Data;
using MyLoop.Api.Entities;
using MyLoop.Api.Models;

namespace MyLoop.Api.Services;

/// <summary>
/// Territory operations — claim processing, territory queries, stolen cells.
/// </summary>
public class TerritoryService : ITerritoryService
{
    private readonly AppDbContext _db;
    private readonly IHexGridService _hexGrid;
    private readonly IGeoService _geo;

    public TerritoryService(AppDbContext db, IHexGridService hexGrid, IGeoService geo)
    {
        _db = db;
        _hexGrid = hexGrid;
        _geo = geo;
    }

    public async Task<ClaimResult> ProcessClaim(Guid userId, double[][] path)
    {
        // Validate: need at least 10 GPS readings
        if (path.Length < GameConstants.MinGpsPointsPerClaim)
        {
            return Fail("Path too short — need at least 10 GPS points");
        }

        // Validate: path must be at least 200m (anti-abuse)
        var totalDistance = _geo.CalculatePathDistance(path);
        if (totalDistance < GameConstants.MinWalkDistanceMeters)
        {
            return Fail("Walk at least 200 meters before claiming");
        }

        // Validate: enforce daily claim cap (anti-abuse)
        var todayStart = DateTime.UtcNow.Date;
        var todayClaimCount = await _db.Claims
            .CountAsync(c => c.UserId == userId && c.CreatedAt >= todayStart);
        if (todayClaimCount >= GameConstants.MaxClaimsPerDay)
        {
            return Fail($"Daily limit reached — max {GameConstants.MaxClaimsPerDay} claims per day");
        }

        // Compute captured hexes (trail + fill)
        var cells = _hexGrid.ComputeCapturedCells(path);
        if (cells.Count == 0)
        {
            return Fail("No hexes captured — try walking further");
        }

        // Anti-abuse: cap at 5 km² to prevent GPS spoofing
        var area = _hexGrid.CalculateArea(cells.Count);
        if (area > GameConstants.MaxClaimAreaSquareMeters)
        {
            return Fail("Claim too large — max 5km² per claim");
        }

        // Create the claim record
        var claim = new Claim
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            CellCount = cells.Count,
            AreaM2 = area,
        };
        claim.SetPolygon(path);

        // Assign hexes to the user and record transfers
        var transfers = new List<CellTransfer>();
        var boundaries = new List<double[][]>();

        foreach (var hexCell in cells)
        {
            var center = _hexGrid.GetCellCenter(hexCell.CellId);
            var parentId = _hexGrid.GetParentCellId(hexCell.CellId);

            var existing = await _db.TerritoryCells.FindAsync(hexCell.CellId);
            if (existing != null)
            {
                // Steal: overwrite the previous owner
                var transfer = new CellTransfer
                {
                    Id = Guid.NewGuid(),
                    CellId = hexCell.CellId,
                    FromUserId = existing.OwnerId == userId ? null : existing.OwnerId,
                    ToUserId = userId,
                    ClaimId = claim.Id,
                    TransferredAt = DateTime.UtcNow,
                };
                transfers.Add(transfer);

                existing.OwnerId = userId;
                existing.ClaimId = claim.Id;
                existing.ClaimedAt = DateTime.UtcNow;
                existing.CenterLat = center.Lat;
                existing.CenterLng = center.Lng;
                existing.ParentCellId = parentId;
                existing.SetBoundary(hexCell.Boundary);
            }
            else
            {
                // Fresh hex — nobody owned it yet
                var cell = new TerritoryCell
                {
                    CellId = hexCell.CellId,
                    OwnerId = userId,
                    ClaimId = claim.Id,
                    ClaimedAt = DateTime.UtcNow,
                    CenterLat = center.Lat,
                    CenterLng = center.Lng,
                    ParentCellId = parentId,
                };
                cell.SetBoundary(hexCell.Boundary);
                _db.TerritoryCells.Add(cell);

                var transfer = new CellTransfer
                {
                    Id = Guid.NewGuid(),
                    CellId = hexCell.CellId,
                    FromUserId = null,
                    ToUserId = userId,
                    ClaimId = claim.Id,
                    TransferredAt = DateTime.UtcNow,
                };
                transfers.Add(transfer);
            }

            boundaries.Add(hexCell.Boundary);
        }

        _db.CellTransfers.AddRange(transfers);
        _db.Claims.Add(claim);

        // Update the claiming user's hex count (net cells owned after this claim)
        var user = await _db.Users.FindAsync(userId);
        if (user != null)
        {
            var newCells = transfers.Count(t => t.FromUserId == null);
            var stolenCells = transfers.Count(t => t.FromUserId != null);
            user.HexCount += newCells + stolenCells;

            // Update total distance walked
            user.DistanceKm += totalDistance / 1000.0;

            // Update streak: consecutive days with at least one claim
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            if (user.LastClaimDate == null || user.LastClaimDate < today.AddDays(-1))
            {
                // First claim ever, or streak broken (gap > 1 day)
                user.Streak = 1;
            }
            else if (user.LastClaimDate == today.AddDays(-1))
            {
                // Consecutive day — extend streak
                user.Streak += 1;
            }
            // else: same day, streak unchanged

            user.LastClaimDate = today;
            if (user.Streak > user.MaxStreak)
            {
                user.MaxStreak = user.Streak;
            }

            // Decrement hex counts for users who lost cells
            var stolenByUser = transfers
                .Where(t => t.FromUserId != null && t.FromUserId != userId)
                .GroupBy(t => t.FromUserId!.Value);
            foreach (var group in stolenByUser)
            {
                var victim = await _db.Users.FindAsync(group.Key);
                if (victim != null)
                {
                    victim.HexCount = Math.Max(0, victim.HexCount - group.Count());
                }
            }
        }

        await _db.SaveChangesAsync();

        var stolenCount = transfers.Count(t => t.FromUserId != null);

        var response = new ClaimResponse
        {
            Id = claim.Id,
            CellCount = claim.CellCount,
            AreaM2 = claim.AreaM2,
            StolenFromOthers = stolenCount,
            Boundaries = boundaries,
        };

        return new ClaimResult { Success = true, Data = response };
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
                t.CellId,
                t.BoundaryJson,
                t.OwnerId,
                OwnerColor = t.Owner!.Color,
                OwnerName = t.Owner!.DisplayName
            })
            .ToListAsync();

        var result = new List<TerritoryCellResponse>();
        foreach (var t in filtered)
        {
            result.Add(new TerritoryCellResponse
            {
                CellId = t.CellId,
                Boundary = JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
                OwnerId = t.OwnerId,
                OwnerColor = t.OwnerColor,
                OwnerName = t.OwnerName,
            });
        }
        return result;
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

    private static ClaimResult Fail(string error)
    {
        return new ClaimResult { Success = false, Error = error };
    }

    public async Task<List<TerritoryCellResponse>> GetUserTerritories(Guid userId)
    {
        var cells = await _db.TerritoryCells
            .Include(t => t.Owner)
            .Where(t => t.OwnerId == userId)
            .Select(t => new
            {
                t.CellId,
                t.BoundaryJson,
                t.OwnerId,
                OwnerColor = t.Owner!.Color,
                OwnerName = t.Owner!.DisplayName
            })
            .ToListAsync();

        return cells.Select(t => new TerritoryCellResponse
        {
            CellId = t.CellId,
            Boundary = System.Text.Json.JsonSerializer.Deserialize<double[][]>(t.BoundaryJson),
            OwnerId = t.OwnerId,
            OwnerColor = t.OwnerColor,
            OwnerName = t.OwnerName,
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
}
