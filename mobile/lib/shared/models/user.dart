/// User model for the MyLoop application.
///
/// Represents a registered player in the system. Maps directly to the
/// `User` entity returned by the .NET backend API.
/// Fields include identity (Firebase UID), display preferences (name, color,
/// avatar), and are serializable to/from JSON for API communication.
library;

/// The application user model, mirroring the backend `User` entity.
///
/// Used throughout the app to represent the currently signed-in player
/// and other players visible on the leaderboard or territory map.
class AppUser {
  final String id;
  final String firebaseUid;
  final String displayName;
  final String color; // hex color like #FF5733
  final int avatarId;

  const AppUser({
    required this.id,
    required this.firebaseUid,
    required this.displayName,
    required this.color,
    required this.avatarId,
  });

  /// Deserializes a user from a JSON map returned by the API.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      firebaseUid: json['firebaseUid'] as String,
      displayName: json['displayName'] as String,
      color: json['color'] as String,
      avatarId: json['avatarId'] as int,
    );
  }

  /// Serializes this user to a JSON map for API requests.
  Map<String, dynamic> toJson() => {
    'id': id,
    'firebaseUid': firebaseUid,
    'displayName': displayName,
    'color': color,
    'avatarId': avatarId,
  };
}
