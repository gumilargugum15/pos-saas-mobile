import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/user.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._api);

  final ApiClient _api;

  /// `POST /auth/login` → `{user, token}`.
  Future<({User user, String token})> login(String email, String password) async {
    final response = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      parse: (data) {
        final json = Json.asMap(data);
        return (
          user: UserModel.fromJson(Json.asMap(json['user'])),
          token: Json.asString(json['token']),
        );
      },
    );
    return response.data;
  }

  Future<User> me() async {
    final response = await _api.get('/auth/me', parse: (data) => UserModel.fromJson(Json.asMap(data)));
    return response.data;
  }

  Future<void> logout() => _api.post('/auth/logout', parse: (_) {});
}
