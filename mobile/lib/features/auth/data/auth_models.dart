import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

class User {
  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.callingNumber,
    this.teamId,
    this.teamName,
    this.isActive = true,
    this.lastLoginAt,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: asString(j['id']),
    fullName: asString(j['full_name']),
    email: asString(j['email']),
    phone: asStringOrNull(j['phone']),
    callingNumber: asStringOrNull(j['calling_number']),
    role: UserRole.fromValue(j['role']),
    teamId: asStringOrNull(j['team_id']),
    teamName: asStringOrNull(j['team_name']),
    isActive: asBool(j['is_active'], true),
    lastLoginAt: parseDate(j['last_login_at']),
    createdAt: parseDate(j['created_at']),
  );

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? callingNumber;
  final UserRole role;
  final String? teamId;
  final String? teamName;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  String get firstName => fullName.trim().split(' ').first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'calling_number': callingNumber,
    'role': role.value,
    'team_id': teamId,
    'team_name': teamName,
    'is_active': isActive,
    'last_login_at': dateToJson(lastLoginAt),
    'created_at': dateToJson(createdAt),
  };
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken, required this.expiresIn, required this.user});

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
    accessToken: asString(j['access_token']),
    refreshToken: asString(j['refresh_token']),
    expiresIn: asInt(j['expires_in']),
    user: User.fromJson(asMap(j['user'])),
  );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final User user;
}

class UserSession {
  const UserSession({
    required this.id,
    this.deviceName,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.current = false,
  });

  factory UserSession.fromJson(Map<String, dynamic> j) => UserSession(
    id: asString(j['id']),
    deviceName: asStringOrNull(j['device_name']),
    createdAt: parseDate(j['created_at']),
    lastUsedAt: parseDate(j['last_used_at']),
    expiresAt: parseDate(j['expires_at']),
    current: asBool(j['current']),
  );

  final String id;
  final String? deviceName;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final bool current;
}
