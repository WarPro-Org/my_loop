// User model - matches the API entity
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

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      firebaseUid: json['firebaseUid'] as String,
      displayName: json['displayName'] as String,
      color: json['color'] as String,
      avatarId: json['avatarId'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'firebaseUid': firebaseUid,
    'displayName': displayName,
    'color': color,
    'avatarId': avatarId,
  };
}
