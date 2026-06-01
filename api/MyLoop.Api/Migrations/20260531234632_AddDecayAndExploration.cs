using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace MyLoop.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddDecayAndExploration : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "CellTransfers",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CellId = table.Column<long>(type: "bigint", nullable: false),
                    FromUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ToUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClaimId = table.Column<Guid>(type: "uuid", nullable: false),
                    TransferredAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CellTransfers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DeviceTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Token = table.Column<string>(type: "text", nullable: false),
                    Platform = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    LastUsedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeviceTokens", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FirebaseUid = table.Column<string>(type: "text", nullable: false),
                    DisplayName = table.Column<string>(type: "text", nullable: false),
                    Color = table.Column<string>(type: "text", nullable: false),
                    AvatarId = table.Column<int>(type: "integer", nullable: false),
                    HexCount = table.Column<int>(type: "integer", nullable: false),
                    TotalHexesCaptured = table.Column<int>(type: "integer", nullable: false),
                    Streak = table.Column<int>(type: "integer", nullable: false),
                    DistanceKm = table.Column<double>(type: "double precision", nullable: false),
                    MaxStreak = table.Column<int>(type: "integer", nullable: false),
                    TopThreeFinishes = table.Column<int>(type: "integer", nullable: false),
                    TopTenFinishes = table.Column<int>(type: "integer", nullable: false),
                    TopHundredFinishes = table.Column<int>(type: "integer", nullable: false),
                    TopThousandFinishes = table.Column<int>(type: "integer", nullable: false),
                    IsStreakActive = table.Column<bool>(type: "boolean", nullable: false),
                    LastClaimDate = table.Column<DateOnly>(type: "date", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    City = table.Column<string>(type: "text", nullable: false),
                    Country = table.Column<string>(type: "text", nullable: false),
                    AuthProvider = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Claims",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CellCount = table.Column<int>(type: "integer", nullable: false),
                    AreaM2 = table.Column<double>(type: "double precision", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    PolygonJson = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Claims", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Claims_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ExploredCells",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CellId = table.Column<long>(type: "bigint", nullable: false),
                    NeighborhoodId = table.Column<long>(type: "bigint", nullable: false),
                    FirstVisitedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ExploredCells", x => new { x.UserId, x.CellId });
                    table.ForeignKey(
                        name: "FK_ExploredCells_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "LeaderboardEntries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Date = table.Column<DateOnly>(type: "date", nullable: false),
                    CellCount = table.Column<int>(type: "integer", nullable: false),
                    AreaM2 = table.Column<double>(type: "double precision", nullable: false),
                    Rank = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LeaderboardEntries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_LeaderboardEntries_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TerritoryCells",
                columns: table => new
                {
                    CellId = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    OwnerId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClaimId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClaimedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CooldownExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CenterLat = table.Column<double>(type: "double precision", nullable: false),
                    CenterLng = table.Column<double>(type: "double precision", nullable: false),
                    ParentCellId = table.Column<long>(type: "bigint", nullable: false),
                    LastRefreshedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    BoundaryJson = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TerritoryCells", x => x.CellId);
                    table.ForeignKey(
                        name: "FK_TerritoryCells_Claims_ClaimId",
                        column: x => x.ClaimId,
                        principalTable: "Claims",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_TerritoryCells_Users_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CellTransfers_CellId",
                table: "CellTransfers",
                column: "CellId");

            migrationBuilder.CreateIndex(
                name: "IX_CellTransfers_FromUserId_TransferredAt",
                table: "CellTransfers",
                columns: new[] { "FromUserId", "TransferredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_CellTransfers_ToUserId_TransferredAt",
                table: "CellTransfers",
                columns: new[] { "ToUserId", "TransferredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_Claims_UserId",
                table: "Claims",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_ExploredCells_NeighborhoodId",
                table: "ExploredCells",
                column: "NeighborhoodId");

            migrationBuilder.CreateIndex(
                name: "IX_ExploredCells_UserId_NeighborhoodId",
                table: "ExploredCells",
                columns: new[] { "UserId", "NeighborhoodId" });

            migrationBuilder.CreateIndex(
                name: "IX_LeaderboardEntries_Date_Rank",
                table: "LeaderboardEntries",
                columns: new[] { "Date", "Rank" });

            migrationBuilder.CreateIndex(
                name: "IX_LeaderboardEntries_UserId_Date",
                table: "LeaderboardEntries",
                columns: new[] { "UserId", "Date" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TerritoryCells_CenterLat_CenterLng",
                table: "TerritoryCells",
                columns: new[] { "CenterLat", "CenterLng" });

            migrationBuilder.CreateIndex(
                name: "IX_TerritoryCells_ClaimId",
                table: "TerritoryCells",
                column: "ClaimId");

            migrationBuilder.CreateIndex(
                name: "IX_TerritoryCells_OwnerId",
                table: "TerritoryCells",
                column: "OwnerId");

            migrationBuilder.CreateIndex(
                name: "IX_TerritoryCells_ParentCellId",
                table: "TerritoryCells",
                column: "ParentCellId");

            migrationBuilder.CreateIndex(
                name: "IX_Users_FirebaseUid",
                table: "Users",
                column: "FirebaseUid",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "CellTransfers");

            migrationBuilder.DropTable(
                name: "DeviceTokens");

            migrationBuilder.DropTable(
                name: "ExploredCells");

            migrationBuilder.DropTable(
                name: "LeaderboardEntries");

            migrationBuilder.DropTable(
                name: "TerritoryCells");

            migrationBuilder.DropTable(
                name: "Claims");

            migrationBuilder.DropTable(
                name: "Users");
        }
    }
}
