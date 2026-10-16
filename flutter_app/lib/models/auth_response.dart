import 'user_model.dart';

/// Data class representing authentication result with JWT token and user info.
class AuthResponse {
  final String token;
  final String? refreshToken;
  final UserModel user;

  const AuthResponse({
    required this.token,
    this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] ?? json['accessToken'] ?? '').toString();
    final refreshToken = json['refreshToken'] as String?;
    final userMap = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : <String, dynamic>{};

    return AuthResponse(
      token: token,
      refreshToken: refreshToken,
      user: UserModel.fromJson(userMap),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      if (refreshToken != null) 'refreshToken': refreshToken,
      'user': user.toJson(),
    };
  }

  @override
  String toString() => 'AuthResponse(token: ${token.isNotEmpty ? "[PROTECTED]" : "empty"}, user: $user)';
}
