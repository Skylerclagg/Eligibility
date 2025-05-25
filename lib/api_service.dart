import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class RobotEventsApiService {
  static const _base = 'https://www.robotevents.com/api/v2';
  // !! IMPORTANT: Replace with your actual RobotEvents API token !!
  static const _token = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIzIiwianRpIjoiYTYwYjQ3MmRiYTM0YWQ3ZWYzY2NjMzQwYTJhNzFjODU3NzFlZWMzODdjOTUwOGMzNzZiYzNhYjYzMzFjNjAzOTc2ZDhiNjZhNGQ2NjBiODUiLCJpYXQiOjE3NDQ4NDQ0NDguMzM5MTY3MSwibmJmIjoxNzQ0ODQ0NDQ4LjMzOTE2OSwiZXhwIjoyNjkxNTI5MjQ4LjMzNDE2Niwic3ViIjoiNDM5MDAiLCJzY29wZXMiOltdfQ.IBhEgzW--z2Z6lKUAtVY6LMUEoKinTB3gpyrkxOzosCo1UW4poY_YUZnFbV062oIrqqkCRXKH4SaI7qVfoIucPu9UHqT8ITeib9pI7UsGe9Of_bKbVcCaMBKDOXbJ5S0gzc3Wo4kFXwpkDME0E89ZzFep1LwXYCLKh0n0uKFslycDl9GOg8cgHXIT6gXkL-Y9XmD5giGp38a89zgbtfigcX5zSSYFuCkMo3Xz_xnHIa6Mae3fY1YIgOElLoB7WBRJrQ5gQsZMURaSH0iyaqIsVcMHpzRUWwTAPr4UQHkgt0cecBTuh5dpn15Iw67eoMA7YnZzD4euT_GmJkBzHeoiZfIlMdUJTLJQvLXXPAAoFg7j1SG6moPrPa9zJXtJWAPTK_QtdA7PdpmemJA9Ya6sQ0BdRn5imUdIRjit9D4R2a9OlQ-FG2YdSTDU203FojYrRXp0WQSBOx_mWUAfl94bCk75rdZo4nLKRdk76VEWIp-DeKAbOOm7MFC44gaYTJERZk4lOCA988imyxvkwfd19fQsYEECoFj2mlwOn0kWpZoYAylAYOgDfSmAcyzDkKOZaleNv1c32LXQzRtRGcbptCxVuHbZow_gWHs-avjMmgHzqzmlu7PCxOCVkXfZPxa5YeFAWPWqT8QliKH8ajsX_ZgDNlGoNYXiApfio8cWmw';

  final RobotProgram program;
  final Season season; // NEW: Now takes a Season object
  RobotEventsApiService({required this.program, required this.season});

  Future<List<T>> _getList<T>(
      String path, T Function(Map<String, dynamic>) fromJson) async {
    final uri = Uri.parse('$_base$path');
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    });
    if (resp.statusCode != 200) {
      print('API $path failed: ${resp.statusCode}, ${resp.body}');
      throw Exception('API $path failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['data'] as List<dynamic>)
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // NEW: Fetch all seasons for a program (used in settings)
  Future<List<Season>> fetchSeasons(int programId) => _getList(
      '/seasons?program[]=$programId&per_page=250', Season.fromJson);


  // Uses dynamic program.id and season.id
  Future<List<EventInfo>> fetchEvents() => _getList(
      '/events?program[]=${program.id}&season[]=${season.id}&per_page=250',
      EventInfo.fromJson);

  // Uses dynamic program.id and season.id
  Future<EventInfo?> fetchEventBySku(String sku) => _getList(
          '/events?sku[]=$sku&program[]=${program.id}&season[]=${season.id}&per_page=250',
          EventInfo.fromJson)
      .then((l) => l.isEmpty ? null : l.first);

  Future<List<Division>> fetchDivisions(int eId) async {
    final uri = Uri.parse('$_base/events/$eId');
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    });
    if (resp.statusCode != 200) {
      throw Exception('Event/$eId failed: ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return (json['divisions'] as List<dynamic>? ?? [])
        .map((d) => Division.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  Future<List<Team>> fetchTeams(int eId) =>
      _getList('/events/$eId/teams?per_page=250', Team.fromJson);

  Future<List<RawSkill>> fetchRawSkills(int eId) =>
      _getList('/events/$eId/skills?per_page=250', RawSkill.fromJson);

  Future<List<Award>> fetchAwards(int eId) =>
      _getList('/events/$eId/awards?per_page=250', Award.fromJson);

  Future<List<Ranking>> fetchRankings(int eId, int divId) async {
    List<Ranking> all = [];
    int page = 1;

    while (true) {
      final uri = Uri.parse(
        '$_base/events/$eId/divisions/$divId/rankings?page=$page&per_page=250',
      );
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      });

      if (resp.statusCode != 200) {
        print('❌ Rankings API error (${resp.statusCode}): ${resp.body}');
        throw Exception('Failed to fetch rankings');
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>;

      if (data.isEmpty) break;

      all.addAll(data.map((e) => Ranking.fromJson(e as Map<String, dynamic>)));
      if (data.length < 250) break;

      print('📄 Fetched page $page with ${data.length} rankings');
      page++;
    }

    print('✅ Total rankings fetched: ${all.length}');
    return all;
  }
}