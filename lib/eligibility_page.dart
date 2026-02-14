// lib/eligibility_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'models.dart'; // Will use the updated models
import 'mobile_eligibility_view.dart';

enum SortableColumn {
  teamNumber,
  teamName,
  organization,
  state,
  qualifierRank,
  skillsRank,
  driverScore,
  programmingScore,
  eligible,
  grade,
  pilotAttempts,
  autonAttempts,
  details, // Not sortable, just for column visibility control
  // We could add programmingOnlyRank for sorting if desired later
}

class EligibilityPage extends StatefulWidget {
  const EligibilityPage({super.key});
  @override
  State<EligibilityPage> createState() => _EligibilityPageState();
}

class _EligibilityPageState extends State<EligibilityPage> {
  // ... (State variables and methods like initState, dispose, loadInitialSettings, etc. remain mostly the same) ...
  late RobotEventsApiService api;
  final skuCtrl = TextEditingController();
  final searchCtrl = TextEditingController();
  late final FocusNode _keyFocusNode;
  final _formKey = GlobalKey<FormState>();

  List<EventInfo> events = [];
  EventInfo? selectedEvent;
  List<Division> divisions = [];
  Division? selectedDivision;

  List<Team> teams = [];
  List<Ranking> rawRankings = [];
  List<RawSkill> rawSkills = [];
  List<Award> awards = [];

  bool loading = false;
  String? error;
  bool hideNoData = false;

  RobotProgram? _selectedProgram;
  ProgramRules? _programRules;
  List<Season> _availableSeasons = [];
  Season? _selectedSeason;

  SortableColumn? _sortColumn;
  bool _sortAscending = true;

  bool _isAutoReloadEnabled = true;
  Timer? _autoReloadTimer;
  static const String _autoReloadPrefKey = 'autoReloadEnabled';

  bool _eventHasSplitGradeAwards = false;
  bool _forceSplitExcellence = false;
  bool _isMobileViewEnabled = false;
  static const String _mobileViewPrefKey = 'mobileViewEnabled';

  double? _userLatitude;
  double? _userLongitude;
  String? _userRegion; // Full state/region name from IP API (e.g., "West Virginia")

  final eventSearchCtrl = TextEditingController(); // For event search in modal

  // Text size and column visibility settings
  double _textScaleFactor = 1.0;
  static const String _textScalePrefKey = 'textScaleFactor';

  Map<SortableColumn, bool> _columnVisibility = {};
  static const String _columnVisibilityPrefKey = 'columnVisibility';

  // Row color cycling for manual highlighting
  Map<int, int> _rowColorState = {};  // teamId -> colorIndex (0=none, 1=green, 2=yellow, 3=red)
  static const String _rowColorStatePrefKey = 'rowColorState';

  // Color definitions for manual row highlighting
  static const List<Color> _rowHighlightColors = [
    Colors.transparent,           // 0 = no manual highlight
    Color(0xFF4CAF50),           // 1 = green (Material Green 500)
    Color(0xFFFFD700),           // 2 = yellow (Gold - more vibrant)
    Color(0xFFF44336),           // 3 = red (Material Red 500)
  ];

  // Award assignment system
  Map<int, String> _teamAwards = {};  // teamId -> awardName
  static const String _teamAwardsPrefKey = 'teamAwards';


  // Program enable/disable state
  Map<RobotProgram, bool> _programEnabled = {};
  static const String _programEnabledPrefKey = 'programEnabled';

  @override
  void initState() {
    super.initState();
    _keyFocusNode = FocusNode();
    _initializeColumnVisibility();
    _initializeProgramEnabled();
    _getUserLocation(); // Fetch user location in background
    _loadInitialSettingsAndData();
  }

  void _initializeColumnVisibility() {
    _columnVisibility = {
      for (var col in SortableColumn.values)
        col: true // Default all columns to visible
    };
  }

  void _initializeProgramEnabled() {
    _programEnabled = {
      for (var program in RobotProgram.values)
        program: program.enabledByDefault
    };
  }

  Future<void> _loadColumnVisibility(SharedPreferences prefs) async {
    final String? saved = prefs.getString(_columnVisibilityPrefKey);
    if (saved != null) {
      try {
        final Map<String, dynamic> savedMap = jsonDecode(saved);
        for (var entry in savedMap.entries) {
          final SortableColumn? column = SortableColumn.values.asNameMap()[entry.key];
          if (column != null && entry.value is bool) {
            _columnVisibility[column] = entry.value;
          }
        }
      } catch (e) {
        print('Failed to load column visibility: $e');
      }
    }
  }

  Future<void> _saveColumnVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> stringMap = _columnVisibility.map((key, value) => MapEntry(key.name, value));
    await prefs.setString(_columnVisibilityPrefKey, jsonEncode(stringMap));
  }

  Future<void> _loadRowColorState(SharedPreferences prefs) async {
    final String? saved = prefs.getString(_rowColorStatePrefKey);
    if (saved != null) {
      try {
        final Map<String, dynamic> savedMap = jsonDecode(saved);
        _rowColorState = savedMap.map((key, value) =>
          MapEntry(int.parse(key), value as int)
        );
      } catch (e) {
        print('Failed to load row color state: $e');
        _rowColorState = {};
      }
    }
  }

  Future<void> _saveRowColorState() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, int> stringMap = _rowColorState.map(
      (key, value) => MapEntry(key.toString(), value)
    );
    await prefs.setString(_rowColorStatePrefKey, jsonEncode(stringMap));
  }

  Future<void> _loadTeamAwards(SharedPreferences prefs) async {
    final String? saved = prefs.getString(_teamAwardsPrefKey);
    if (saved != null) {
      try {
        final Map<String, dynamic> savedMap = jsonDecode(saved);
        _teamAwards = savedMap.map((key, value) =>
          MapEntry(int.parse(key), value as String)
        );
      } catch (e) {
        print('Failed to load team awards: $e');
        _teamAwards = {};
      }
    }
  }

  Future<void> _saveTeamAwards() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> stringMap = _teamAwards.map(
      (key, value) => MapEntry(key.toString(), value)
    );
    await prefs.setString(_teamAwardsPrefKey, jsonEncode(stringMap));
  }

  Future<void> _loadProgramEnabled(SharedPreferences prefs) async {
    final String? saved = prefs.getString(_programEnabledPrefKey);
    if (saved != null) {
      try {
        final Map<String, dynamic> savedMap = jsonDecode(saved);
        for (var entry in savedMap.entries) {
          final RobotProgram? program = RobotProgram.values.asNameMap()[entry.key];
          if (program != null && entry.value is bool) {
            _programEnabled[program] = entry.value;
          }
        }
      } catch (e) {
        print('Failed to load program enabled state: $e');
      }
    }
  }

  Future<void> _saveProgramEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> stringMap = _programEnabled.map((key, value) => MapEntry(key.name, value));
    await prefs.setString(_programEnabledPrefKey, jsonEncode(stringMap));
  }

  @override
  void dispose() {
    _cancelAutoReloadTimer();
    _keyFocusNode.dispose();
    skuCtrl.dispose();
    searchCtrl.dispose();
    eventSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      // Use ip-api.com to get approximate location from IP (free, no API key needed)
      final response = await http.get(Uri.parse('http://ip-api.com/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _userLatitude = (data['lat'] as num?)?.toDouble();
        _userLongitude = (data['lon'] as num?)?.toDouble();
        // RobotEvents API uses full state names, so we use 'regionName' instead of 'region'
        // ip-api returns 'regionName' as the full name (e.g., "West Virginia", "California")
        _userRegion = data['regionName'] as String?;
        print('📍 User location: ${data['city']}, ${data['regionName']} (country: ${data['country']})');
        print('📍 User region for filtering: "$_userRegion"');
      }
    } catch (e) {
      print('⚠️ Could not determine user location: $e');
    }
  }

  double _calculateDistance(double? lat1, double? lon1, double? lat2, double? lon2) {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      return double.infinity; // Place events without coordinates at the end
    }

    // Haversine formula to calculate distance in miles
    const earthRadiusMiles = 3959.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMiles * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  Future<void> _showEventSelectorDialog() async {
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recent events available. Try loading by SKU.')),
      );
      return;
    }

    // Debug: Print event info
    print('🔍 User region: "$_userRegion"');
    print('🔍 Total events: ${events.length}');
    if (events.isNotEmpty) {
      print('🔍 Sample event regions: ${events.take(5).map((e) => '"${e.region}" (${e.name})').toList()}');
      // Check for exact matches
      final exactMatches = events.where((e) => e.region == _userRegion).length;
      print('🔍 Events with exact region match "$_userRegion": $exactMatches');
      // Check for case-insensitive matches
      final caseInsensitiveMatches = events.where((e) => e.region.toUpperCase() == _userRegion?.toUpperCase()).length;
      print('🔍 Events with case-insensitive match: $caseInsensitiveMatches');
    }

    eventSearchCtrl.clear(); // Reset search when opening dialog

    final selected = await showDialog<EventInfo>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            // Apply search filter
            final searchTerm = eventSearchCtrl.text.toLowerCase();
            final filteredEvents = searchTerm.isEmpty
                ? events
                : events.where((e) =>
                    e.name.toLowerCase().contains(searchTerm) ||
                    e.sku.toLowerCase().contains(searchTerm) ||
                    e.city.toLowerCase().contains(searchTerm)
                  ).toList();

            // Pre-sort filtered events for the dialog (case-insensitive comparison)
            final inStateEvents = filteredEvents.where((e) =>
              _userRegion != null && e.region.toUpperCase() == _userRegion!.toUpperCase()
            ).toList();
            final otherEvents = filteredEvents.where((e) =>
              _userRegion == null || e.region.toUpperCase() != _userRegion!.toUpperCase()
            ).toList();

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 650, maxHeight: 700),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary.withOpacity(0.8),
                            Theme.of(context).colorScheme.primaryContainer.withOpacity(0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.event, size: 24, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select Event',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  _selectedSeason?.name ?? '',
                                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: eventSearchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by event name, SKU, or city...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: eventSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    eventSearchCtrl.clear();
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    // Event list
                    Expanded(
                      child: filteredEvents.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No events match your search',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _getEventListItemCount(inStateEvents, otherEvents),
                              itemBuilder: (context, index) => _buildEventListItem(context, index, inStateEvents, otherEvents),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        selectedEvent = selected;
        skuCtrl.text = selected.sku;
      });
      await _loadAllDataForEvent(selected.id);
    }
  }

  int _getEventListItemCount(List<EventInfo> inStateEvents, List<EventInfo> otherEvents) {
    int count = 0;
    if (inStateEvents.isNotEmpty && _userRegion != null) {
      count += 1 + inStateEvents.length; // Header + events
    }
    if (otherEvents.isNotEmpty) {
      if (inStateEvents.isNotEmpty) count += 1; // "Other States" header
      count += otherEvents.length;
    }
    return count;
  }

  Widget _buildEventListItem(BuildContext context, int index, List<EventInfo> inStateEvents, List<EventInfo> otherEvents) {
    int currentIndex = index;

    // Your State section
    if (inStateEvents.isNotEmpty && _userRegion != null) {
      if (currentIndex == 0) {
        // Section header
        return Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.location_on, size: 18, color: Colors.blue[400]),
              ),
              const SizedBox(width: 10),
              Text(
                'Your State ($_userRegion) • ${inStateEvents.length} event${inStateEvents.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[400],
                ),
              ),
            ],
          ),
        );
      }
      currentIndex -= 1;

      if (currentIndex < inStateEvents.length) {
        return _buildEventCard(context, inStateEvents[currentIndex]);
      }
      currentIndex -= inStateEvents.length;
    }

    // Other States section
    if (inStateEvents.isNotEmpty && currentIndex == 0) {
      // Section header
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.public, size: 18, color: Colors.grey[500]),
            ),
            const SizedBox(width: 10),
            Text(
              'Other States • ${otherEvents.length} event${otherEvents.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    if (inStateEvents.isNotEmpty) currentIndex -= 1;

    return _buildEventCard(context, otherEvents[currentIndex]);
  }

  Widget _buildEventCard(BuildContext context, EventInfo e) {
    final dateLabel = '${e.start.month}/${e.start.day}/${e.start.year}';
    final isSelected = selectedEvent?.id == e.id;
    final isCanceled = e.isCanceled;

    // Determine status color and icon
    final status = e.status;
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'Canceled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'Live':
        statusColor = Colors.green;
        statusIcon = Icons.podcasts;
        break;
      case 'Completed':
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle;
        break;
      default: // Upcoming
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
    }

    // Text color for canceled events
    final textColor = isCanceled ? Colors.red : Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = isCanceled ? Colors.red.withOpacity(0.7) : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(e),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Event info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: textColor,
                              decoration: isCanceled ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.red,
                              decorationThickness: 2.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: statusColor, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.confirmation_number, size: 13, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Text(
                            e.sku,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              decoration: isCanceled ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.calendar_today, size: 13, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              decoration: isCanceled ? TextDecoration.lineThrough : null,
                              decorationColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      if (e.city.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.place, size: 13, color: isCanceled ? Colors.red.withOpacity(0.6) : Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${e.city}, ${e.region}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCanceled ? Colors.red.withOpacity(0.6) : Colors.grey[500],
                                  decoration: isCanceled ? TextDecoration.lineThrough : null,
                                  decorationColor: Colors.red,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Trailing icon
                Icon(
                  isSelected ? Icons.check_circle : Icons.arrow_forward_ios,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[400],
                  size: isSelected ? 26 : 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadInitialSettingsAndData() async {
    // ... (implementation is the same)
    if (!mounted) return;
    setState(() { loading = true; error = null; });

    final prefs = await SharedPreferences.getInstance();
    final savedProgramId = prefs.getInt('selectedProgramId');
    final savedSeasonId = prefs.getInt('selectedSeasonId');
    _isAutoReloadEnabled = prefs.getBool(_autoReloadPrefKey) ?? true;
    _isMobileViewEnabled = prefs.getBool(_mobileViewPrefKey) ?? false;
    _textScaleFactor = prefs.getDouble(_textScalePrefKey) ?? 1.0;

    // Load column visibility settings
    await _loadColumnVisibility(prefs);
    await _loadRowColorState(prefs);
    await _loadTeamAwards(prefs);
    await _loadProgramEnabled(prefs);

    RobotProgram initialProgram = RobotProgram.values.firstWhere(
        (p) => p.id == savedProgramId, orElse: () => RobotProgram.v5rc);

    RobotEventsApiService tempApi = RobotEventsApiService(
        program: initialProgram,
        season: Season(id: -1, name: 'temp', programName: 'temp'));

    try {
      List<Season> fetchedSeasons = await tempApi.fetchSeasons(initialProgram.id);
      fetchedSeasons.sort((a, b) => b.id.compareTo(a.id));

      Season initialSeason;
      if (fetchedSeasons.isNotEmpty) {
        _availableSeasons = fetchedSeasons;
        initialSeason = _availableSeasons.firstWhere(
            (s) => s.id == savedSeasonId, orElse: () => _availableSeasons.first);
      } else {
        _availableSeasons = [];
        initialSeason = Season(id: 192, name: '2024-2025 (Default)', programName: initialProgram.name);
        _availableSeasons.add(initialSeason);
      }

      if (!mounted) return;
      setState(() {
        _selectedProgram = initialProgram;
        _programRules = ProgramRules.forProgram(_selectedProgram!); // This will now include new rules
        _selectedSeason = initialSeason;
        api = RobotEventsApiService(program: _selectedProgram!, season: _selectedSeason!);
      });

      if (savedProgramId == null || savedSeasonId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) await _showSettingsDialog();
        });
      } else {
        await _loadEvents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Failed to load initial settings: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await _showSettingsDialog();
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _keyFocusNode.requestFocus();
      }
    }
  }
  
  void _manageAutoReloadTimer() {
    // ... (implementation is the same)
    _cancelAutoReloadTimer();
    if (_isAutoReloadEnabled && selectedEvent != null && mounted) {
      _autoReloadTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
        if (mounted && selectedEvent != null && !loading) {
          _loadAllDataForEvent(selectedEvent!.id, isAutoReload: true);
        }
      });
    }
  }

  void _cancelAutoReloadTimer() {
    // ... (implementation is the same)
    _autoReloadTimer?.cancel();
    _autoReloadTimer = null;
  }

  Future<void> _loadEvents() async {
    // ... (implementation is the same)
    if (_selectedProgram == null || _selectedSeason == null) {
      if (!mounted) return;
      setState(() => error = 'Program or Season not selected.');
      return;
    }
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      print('📡 Starting to fetch events...');
      final all = await api.fetchEvents();
      print('📊 Received ${all.length} total events from API');

      final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      events = all.where((e) => e.start.isAfter(oneWeekAgo) || e.start.isAtSameMomentAs(oneWeekAgo)).toList();
      print('🔢 After filtering: ${events.length} events in last 7 days');

      // Sort events chronologically (earliest first) with distance as secondary sort
      events.sort((a, b) {
        // Primary sort: chronological order (earliest dates first)
        final dateComparison = a.start.compareTo(b.start);
        if (dateComparison != 0) return dateComparison;

        // Secondary sort: by distance if available
        if (_userLatitude != null && _userLongitude != null) {
          final distanceA = _calculateDistance(_userLatitude, _userLongitude, a.latitude, a.longitude);
          final distanceB = _calculateDistance(_userLatitude, _userLongitude, b.latitude, b.longitude);
          return distanceA.compareTo(distanceB);
        }
        return 0;
      });

      print('📅 Events sorted chronologically (earliest first), then by distance${_userRegion != null ? " (state: $_userRegion)" : ""}');

      if (events.isEmpty) {
        print('⚠️ No events after filtering. Showing error message.');
        setState(() => error = 'No events found in the last 7 days. ${all.length} total events available. Try loading by SKU.');
      } else {
        print('✅ ${events.length} events available for dropdown');
      }
    } catch (e) {
      print('❌ Error loading events: $e');
      if (!mounted) return;
      setState(() => error = 'Failed to load events: $e');
    } finally {
      if (mounted) setState(() => loading = false);
      _manageAutoReloadTimer();
    }
  }

  Future<void> _loadSku() async {
    // ... (implementation is the same)
    final String rawInput = skuCtrl.text.trim();
    final String processedInput = rawInput.toUpperCase();

    if (rawInput.isEmpty) {
      if (!mounted) return;
      setState(() { selectedEvent = null; _clearEventData(resetSort: true); });
      await _loadEvents();
      return;
    }

    if (_selectedProgram == null || _selectedSeason == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a program and season first.')),
      );
      return;
    }
    
    if (!mounted) return;
    setState(() { loading = true; error = null; });

    String skuToSearch;
    final String programSkuPrefix = _selectedProgram!.skuPrefix.toUpperCase();

    if (processedInput.startsWith(programSkuPrefix)) {
      skuToSearch = processedInput;
    } else {
      skuToSearch = programSkuPrefix + processedInput;
    }
    
    if (mounted) {
        if (skuCtrl.text != skuToSearch) {
            skuCtrl.text = skuToSearch;
            skuCtrl.selection = TextSelection.fromPosition(TextPosition(offset: skuCtrl.text.length));
        }
    }

    try {
      final f = await api.fetchEventBySku(skuToSearch);
      if (!mounted) return;
      if (f != null) {
        EventInfo eventToSelect;
        if (!events.any((e) => e.id == f.id)) {
          events.insert(0, f);
          events.sort((a, b) => b.start.compareTo(a.start));
          eventToSelect = events.firstWhere((e) => e.id == f.id);
        } else {
          eventToSelect = events.firstWhere((e) => e.id == f.id);
        }
        setState(() => selectedEvent = eventToSelect);
        await _loadAllDataForEvent(eventToSelect.id); 
      } else {
        setState(() => error = 'Event not found for SKU: $skuToSearch');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Event not found for SKU: $skuToSearch. Check program and season.')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Error loading SKU $skuToSearch: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading event: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  
  void _clearEventData({bool resetSort = false}) {
    // ... (implementation is the same)
     if (!mounted) return;
     setState(() {
        divisions = [];
        selectedDivision = null;
        teams = [];
        rawRankings = [];
        rawSkills = [];
        awards = [];
        _eventHasSplitGradeAwards = false;
        _rowColorState = {};  // Clear manual row colors when event changes
        _teamAwards = {};  // Clear award assignments when event changes
        error = null;
        if (resetSort) {
          _sortColumn = null;
        }
     });
  }

  Future<void> _loadAllDataForEvent(int eventId, {bool isAutoReload = false}) async {
    // ... (implementation is the same)
    if (_programRules == null || _selectedProgram == null) {
      if (!mounted) return;
      setState(() => error = 'Program rules or program not loaded. Please check settings.');
      return;
    }
    if (!mounted) return;
    // Only show loading screen for manual reloads, not auto-reloads
    if (!isAutoReload) {
      setState(() { loading = true; _clearEventData(resetSort: true);});
    }

    try {
      // Fetch data in background (doesn't trigger setState until all is ready)
      List<Division> fetchedDivisions = await api.fetchDivisions(eventId);
      if (fetchedDivisions.isEmpty) {
        fetchedDivisions.add(Division(id: 1, name: 'Default Division'));
      }
      if (!mounted) return;

      List<Team> fetchedTeams = await api.fetchTeams(eventId);
      if (!mounted) return;

      List<Ranking> fetchedRankings = [];
      if (fetchedDivisions.isNotEmpty) {
        fetchedRankings = await api.fetchRankings(eventId, fetchedDivisions.first.id);
      }
      if (!mounted) return;

      List<RawSkill> fetchedSkills = await api.fetchRawSkills(eventId);
      if (!mounted) return;

      List<Award> fetchedAwards = await api.fetchAwards(eventId);
      if (!mounted) return;

      // Update state all at once to minimize re-renders
      divisions = fetchedDivisions;
      selectedDivision = divisions.first;
      teams = fetchedTeams;
      rawRankings = fetchedRankings;
      rawSkills = fetchedSkills;
      awards = fetchedAwards;

      bool detectedSplitAwards = false;
      if (_programRules!.hasMiddleSchoolHighSchoolDivisions) {
        final String baseAwardNameLower = _selectedProgram!.awardName.toLowerCase();

        bool esAwardFound = fetchedAwards.any((awardL) {
          final lower = awardL.title.toLowerCase();
          return lower.contains(baseAwardNameLower) && lower.contains('elementary school');
        });

        bool msAwardFound = fetchedAwards.any((awardL) {
          final lower = awardL.title.toLowerCase();
          return lower.contains(baseAwardNameLower) && lower.contains('middle school');
        });

        bool hsAwardFound = fetchedAwards.any((awardL) {
          final lower = awardL.title.toLowerCase();
          return lower.contains(baseAwardNameLower) && lower.contains('high school');
        });

        detectedSplitAwards = msAwardFound && hsAwardFound || esAwardFound && msAwardFound;
      }
      if(!mounted) return;

      // For auto-reload, update everything in one setState to prevent flickering
      // For manual reload, loading screen is already showing so just update the flag
      _eventHasSplitGradeAwards = detectedSplitAwards;
      if (isAutoReload && mounted) {
        setState(() {});
      }

    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Failed to load data for event $eventId: $e');
    } finally {
      if (mounted) setState(() => loading = false);
      _manageAutoReloadTimer(); 
    }
  }

  bool get isCombinedDivisionEvent {
    if (_programRules == null) return true;
    if (_forceSplitExcellence) return false;
    if (!_programRules!.hasMiddleSchoolHighSchoolDivisions) {
      return true;
    }
    return !_eventHasSplitGradeAwards;
  }

  double get eligibilityThreshold {
    // ... (implementation is the same)
    if (_programRules == null) return 0.5;
    return _programRules!.threshold;
  }

  List<TeamSkills> get tableRecords {
    if (_programRules == null || teams.isEmpty || _selectedProgram == null) return [];

    final Map<int, Team> teamMap = {for (var t in teams) t.id: t};

    Map<int, RawSkill> bestProgrammingRuns = {};
    Map<int, RawSkill> bestDriverRuns = {};

    for (var teamEntry in teamMap.entries) {
        int teamId = teamEntry.key;
        List<RawSkill> teamRawSkills = rawSkills.where((s) => s.teamId == teamId).toList();

        RawSkill? bestProg = teamRawSkills
            .where((s) => s.type == 'programming')
            .fold(null, (RawSkill? prev, current) => (prev == null || current.score > prev.score) ? current : prev);
        if (bestProg != null) bestProgrammingRuns[teamId] = bestProg;

        RawSkill? bestDriver = teamRawSkills
            .where((s) => s.type == 'driver')
            .fold(null, (RawSkill? prev, current) => (prev == null || current.score > prev.score) ? current : prev);
        if (bestDriver != null) bestDriverRuns[teamId] = bestDriver;
    }
    
    List<Map<String, dynamic>> teamsWithCombinedScoresForOverallRank = [];
    for (var teamEntry in teamMap.entries) {
        int teamId = teamEntry.key;
        int combinedScore = (bestProgrammingRuns[teamId]?.score ?? 0) + (bestDriverRuns[teamId]?.score ?? 0);
        if (combinedScore > 0 || bestProgrammingRuns.containsKey(teamId) || bestDriverRuns.containsKey(teamId)) {
             teamsWithCombinedScoresForOverallRank.add({'teamId': teamId, 'combinedScore': combinedScore});
        }
    }
    teamsWithCombinedScoresForOverallRank.sort((a, b) => (b['combinedScore'] as int).compareTo(a['combinedScore'] as int));
    Map<int, int> overallSkillsRanksMap = {};
    for (int i = 0; i < teamsWithCombinedScoresForOverallRank.length; i++) {
        overallSkillsRanksMap[teamsWithCombinedScoresForOverallRank[i]['teamId'] as int] = i + 1;
    }

    Map<String, List<Ranking>> gradeQualifierRankingsMap = {};
    Map<String, List<Map<String,dynamic>>> gradeSkillsRankingsMap = {}; 
    Map<String, List<Map<String,dynamic>>> gradeProgrammingOnlyRankingsMap = {}; // New map for programming-only ranks

    final bool checkProgRankRule = _programRules!.requiresRankInPositiveProgrammingSkills;

    if (!isCombinedDivisionEvent || checkProgRankRule) { // Precompute if either needs grade-specific data
      final Set<String> grades = teams.map((t) => t.grade.toLowerCase()).toSet()..removeWhere((g) => g.isEmpty);
      List<String> contextsToProcess = [];
      if(isCombinedDivisionEvent && checkProgRankRule) { // Only overall context for prog rank if main event is combined
          contextsToProcess.add("overall_for_prog_rank");
      } else if (!isCombinedDivisionEvent) { // Grade specific contexts for prog rank (and others)
          contextsToProcess.addAll(grades);
          if (teams.any((t) => t.grade.isEmpty)) contextsToProcess.add("no_grade_for_prog_rank"); // Handle teams with no grade for prog rank
      }


      for (String gradeOrContext in contextsToProcess) {
        // Qualifier Rankings (only if !isCombinedDivisionEvent)
        if (!isCombinedDivisionEvent && gradeOrContext != "overall_for_prog_rank" && gradeOrContext != "no_grade_for_prog_rank") {
            gradeQualifierRankingsMap[gradeOrContext] = rawRankings
                .where((r) {
                  final rTeam = teamMap[r.teamId];
                  return rTeam != null && rTeam.grade.toLowerCase() == gradeOrContext && r.rank > 0;
                })
                .toList()..sort((a, b) => a.rank.compareTo(b.rank));
        }

        // Combined Skills Re-ranking per grade (only if !isCombinedDivisionEvent)
        if (!isCombinedDivisionEvent && gradeOrContext != "overall_for_prog_rank" && gradeOrContext != "no_grade_for_prog_rank") {
            List<Map<String,dynamic>> gradeTeamsWithCombinedScores = [];
            for (var teamEntry in teamMap.entries) {
                if (teamEntry.value.grade.toLowerCase() == gradeOrContext) {
                    int teamId = teamEntry.key;
                    int combinedScore = (bestProgrammingRuns[teamId]?.score ?? 0) + (bestDriverRuns[teamId]?.score ?? 0);
                    if (combinedScore > 0 || bestProgrammingRuns.containsKey(teamId) || bestDriverRuns.containsKey(teamId) ) {
                        gradeTeamsWithCombinedScores.add({'teamId': teamId, 'combinedScore': combinedScore});
                    }
                }
            }
            gradeTeamsWithCombinedScores.sort((a,b) => (b['combinedScore'] as int).compareTo(a['combinedScore'] as int));
            List<Map<String,dynamic>> gradeSkillRanks = [];
            for(int i=0; i < gradeTeamsWithCombinedScores.length; i++){
                gradeSkillRanks.add({'teamId': gradeTeamsWithCombinedScores[i]['teamId'] as int, 'rank': i+1 });
            }
            gradeSkillsRankingsMap[gradeOrContext] = gradeSkillRanks;
        }

        // Programming Only Skills Re-ranking (for applicable contexts)
        if (checkProgRankRule) {
            List<Map<String,dynamic>> programmingOnlyPool = [];
            for (var teamEntry in teamMap.entries) {
                bool include = false;
                if (gradeOrContext == "overall_for_prog_rank") include = true;
                else if (gradeOrContext == "no_grade_for_prog_rank" && teamEntry.value.grade.isEmpty) include = true;
                else if (teamEntry.value.grade.toLowerCase() == gradeOrContext) include = true;

                if (include) {
                    final progRun = bestProgrammingRuns[teamEntry.key];
                    if (progRun != null && progRun.score > 0) {
                        programmingOnlyPool.add({'teamId': teamEntry.key, 'score': progRun.score});
                    }
                }
            }
            programmingOnlyPool.sort((a,b) => (b['score'] as int).compareTo(a['score'] as int));
            List<Map<String,dynamic>> progOnlyRanks = [];
            for(int i=0; i < programmingOnlyPool.length; i++){
                progOnlyRanks.add({'teamId': programmingOnlyPool[i]['teamId'] as int, 'rank': i+1});
            }
            gradeProgrammingOnlyRankingsMap[gradeOrContext] = progOnlyRanks;
        }
      }
    }


    return teams.map((team) {
      final RawSkill? bestProgRun = bestProgrammingRuns[team.id];
      final RawSkill? bestDriverRun = bestDriverRuns[team.id];
      
      final int teamProgrammingScore = bestProgRun?.score ?? 0;
      final int teamProgrammingAttempts = bestProgRun?.attempts ?? 0;
      final int teamDriverScore = bestDriverRun?.score ?? 0;
      final int teamDriverAttempts = bestDriverRun?.attempts ?? 0;

      final overallRankingData = rawRankings.firstWhere((r) => r.teamId == team.id,
          orElse: () => Ranking(teamId: team.id, rank: -1));

      int displayQualRank = overallRankingData.rank > 0 ? overallRankingData.rank : -1;
      int displaySkillsRank = overallSkillsRanksMap[team.id] ?? -1;
      
      bool isInQualifyingRank;
      bool isInSkillsRank;
      int qualCutoffValue; 
      int skillsCutoffValue; 

      // New variables for programming only rank criteria
      int teamProgrammingOnlyRank = -1;
      int programmingOnlyRankCutoffValue = -1;
      bool meetsProgOnlyRankCriterion = true; // Default to true if rule doesn't apply or team meets it

      if (isCombinedDivisionEvent) { 
        final totalRankedTeamsInDivision = rawRankings.where((r) => r.rank > 0).length;
        qualCutoffValue = max(1, applyProgramSpecificRounding(totalRankedTeamsInDivision * eligibilityThreshold, _selectedProgram!));
        isInQualifyingRank = displayQualRank > 0 && displayQualRank <= qualCutoffValue;

        skillsCutoffValue = max(1, applyProgramSpecificRounding(totalRankedTeamsInDivision * eligibilityThreshold, _selectedProgram!));
        isInSkillsRank = displaySkillsRank > 0 && displaySkillsRank <= skillsCutoffValue;

        if (_programRules!.requiresRankInPositiveProgrammingSkills) {
            // Always calculate the cutoff, even if team doesn't have a programming score
            programmingOnlyRankCutoffValue = max(1, applyProgramSpecificRounding(totalRankedTeamsInDivision * eligibilityThreshold, _selectedProgram!));

            final List<Map<String,dynamic>>? progOnlyPool = gradeProgrammingOnlyRankingsMap["overall_for_prog_rank"];
            if (teamProgrammingScore > 0 && progOnlyPool != null && progOnlyPool.isNotEmpty) {
                final teamEntryInPool = progOnlyPool.firstWhere((e) => e['teamId'] == team.id, orElse: () => {});
                teamProgrammingOnlyRank = teamEntryInPool['rank'] ?? -1;
                meetsProgOnlyRankCriterion = teamProgrammingOnlyRank > 0 && teamProgrammingOnlyRank <= programmingOnlyRankCutoffValue;
            } else {
                meetsProgOnlyRankCriterion = false; // No positive score or no pool
            }
        }

      } else { // Grade-specific logic
        final teamGrade = team.grade.toLowerCase();
        String gradeContextKey = teamGrade.isNotEmpty ? teamGrade : "no_grade_for_prog_rank";
        int gradeSpecificQualifierCount = 0;

        if (teamGrade.isNotEmpty && gradeQualifierRankingsMap.containsKey(teamGrade)) {
            final List<Ranking> gradeQualifiers = gradeQualifierRankingsMap[teamGrade]!;
            gradeSpecificQualifierCount = gradeQualifiers.length;
            qualCutoffValue = max(1, applyProgramSpecificRounding(gradeSpecificQualifierCount * eligibilityThreshold, _selectedProgram!));

            final teamIndexInGradeQual = gradeQualifiers.indexWhere((r) => r.teamId == team.id);
            displayQualRank = (teamIndexInGradeQual != -1) ? teamIndexInGradeQual + 1 : -1;
            isInQualifyingRank = displayQualRank > 0 && displayQualRank <= qualCutoffValue;

            skillsCutoffValue = max(1, applyProgramSpecificRounding(gradeSpecificQualifierCount * eligibilityThreshold, _selectedProgram!));

            final List<Map<String,dynamic>>? gradeSkillsRankList = gradeSkillsRankingsMap[teamGrade];
            final gradeSkillEntryForTeam = gradeSkillsRankList?.firstWhere((s) => s['teamId'] == team.id, orElse: () => {'rank': -1});
            displaySkillsRank = gradeSkillEntryForTeam?['rank'] as int? ?? -1;
            isInSkillsRank = displaySkillsRank > 0 && displaySkillsRank <= skillsCutoffValue;
        } else {
            isInQualifyingRank = false;
            isInSkillsRank = false;
            qualCutoffValue = -1;
            skillsCutoffValue = -1;
            displayQualRank = overallRankingData.rank > 0 ? overallRankingData.rank : -1;
        }

        if (_programRules!.requiresRankInPositiveProgrammingSkills) {
            // Always calculate the cutoff, even if team doesn't have a programming score
            if (gradeSpecificQualifierCount > 0) {
                programmingOnlyRankCutoffValue = max(1, applyProgramSpecificRounding(gradeSpecificQualifierCount * eligibilityThreshold, _selectedProgram!));
            }

            final List<Map<String,dynamic>>? progOnlyPool = gradeProgrammingOnlyRankingsMap[gradeContextKey];
            if (teamProgrammingScore > 0 && progOnlyPool != null && progOnlyPool.isNotEmpty) {
                final teamEntryInPool = progOnlyPool.firstWhere((e) => e['teamId'] == team.id, orElse: () => {});
                teamProgrammingOnlyRank = teamEntryInPool['rank'] ?? -1;
                meetsProgOnlyRankCriterion = teamProgrammingOnlyRank > 0 && teamProgrammingOnlyRank <= programmingOnlyRankCutoffValue;
            } else {
                 meetsProgOnlyRankCriterion = false;
            }
        }
      }

      bool isEligible = isInQualifyingRank &&
                        isInSkillsRank &&
                        meetsProgOnlyRankCriterion && // Add new criterion
                        (_programRules!.requiresProgrammingSkills ? (teamProgrammingScore > 0) : true);

      return TeamSkills(
        team: team,
        qualifierRank: displayQualRank,
        skillsRank: displaySkillsRank,
        programmingScore: teamProgrammingScore,
        driverScore: teamDriverScore,
        programmingAttempts: teamProgrammingAttempts,
        driverAttempts: teamDriverAttempts,
        eligible: isEligible,
        inRank: isInQualifyingRank,
        inSkill: isInSkillsRank,
        qualifierRankCutoff: qualCutoffValue,   
        skillsRankCutoff: skillsCutoffValue, 
        programmingOnlyRank: teamProgrammingOnlyRank,
        programmingOnlyRankCutoff: programmingOnlyRankCutoffValue,
        meetsProgrammingOnlyRankCriterion: meetsProgOnlyRankCriterion,
      );
    }).toList();
  }


  String _formatRank(int rank) => rank < 0 ? 'N/A' : '#$rank';

  Widget _buildSummaryWidget(String? gradeLevelContext) {
    // ... (implementation is the same as previous correct version)
    if (_programRules == null || selectedEvent == null || _selectedProgram == null) return const SizedBox.shrink();

    final recordsForSummary = gradeLevelContext == null
        ? tableRecords
        : tableRecords.where((ts) => ts.team.grade.toLowerCase() == gradeLevelContext.toLowerCase()).toList();

    if (recordsForSummary.isEmpty && gradeLevelContext != null) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text("No ${gradeLevelContext} teams with complete data for summary.", style: Theme.of(context).textTheme.bodySmall));
    }

    int qualCutoffRankDisplay;
    int skillsCutoffRankDisplay; 

    if (isCombinedDivisionEvent || gradeLevelContext == null) { 
      final totalRankedTeamsInQualifiers = rawRankings.where((r)=>r.rank > 0).length;
      qualCutoffRankDisplay = max(1, applyProgramSpecificRounding(totalRankedTeamsInQualifiers * eligibilityThreshold, _selectedProgram!));
      skillsCutoffRankDisplay = max(1, applyProgramSpecificRounding(totalRankedTeamsInQualifiers * eligibilityThreshold, _selectedProgram!));
    } else {
      final grade = gradeLevelContext.toLowerCase();
      final gradeSpecificRankedTeamsInQualifiers = rawRankings.where((r) {
        final teamData = teams.firstWhere((t) => t.id == r.teamId, 
            orElse: () => Team(id: -1, number: '', name: '', grade: '', organization: '', state: '', city: '', country: ''));
        return teamData.grade.toLowerCase() == grade && r.rank > 0;
      }).length;
      qualCutoffRankDisplay = max(1, applyProgramSpecificRounding(gradeSpecificRankedTeamsInQualifiers * eligibilityThreshold, _selectedProgram!));
      skillsCutoffRankDisplay = max(1, applyProgramSpecificRounding(gradeSpecificRankedTeamsInQualifiers * eligibilityThreshold, _selectedProgram!));
    }

    final eligibleTeamNumbers = recordsForSummary.where((ts) => ts.eligible).map((ts) => ts.team.number).toList();
    final summaryText = eligibleTeamNumbers.isEmpty ? 'None' : eligibleTeamNumbers.join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0), elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      color: Theme.of(context).colorScheme.surface.withAlpha(200),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qual. Rank Cutoff (Top ${(eligibilityThreshold * 100).toStringAsFixed(0)}% of ${gradeLevelContext ?? ""} teams): ≤#$qualCutoffRankDisplay'.replaceFirst(" qualifier teams", gradeLevelContext !=null ? " $gradeLevelContext qualifier teams" : " qualifier teams"),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
            Text('Skills Rank Cutoff (Top ${(eligibilityThreshold * 100).toStringAsFixed(0)}% of ${gradeLevelContext ?? ""} teams): Achieve Skills Rank ≤#$skillsCutoffRankDisplay'.replaceFirst(" qualifier teams", gradeLevelContext !=null ? " $gradeLevelContext qualifier teams" : " qualifier teams"),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.emoji_events_outlined, color: Colors.amberAccent[100], size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Eligible for ${_selectedProgram?.awardName ?? "Award"}: $summaryText',
                  style: Theme.of(context).textTheme.titleSmall)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tableSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 4.0, left: 4.0),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
      );

  Widget _buildSortableHeader(SortableColumn column, String title, int flex, {TextAlign textAlign = TextAlign.left}) {
    // ... (implementation is the same as previous correct version)
    bool isActiveSortColumn = _sortColumn == column;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          if (!mounted) return;
          setState(() {
            if (isActiveSortColumn) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumn = column;
              _sortAscending = true;
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: textAlign == TextAlign.center ? MainAxisAlignment.center : (textAlign == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start),
            children: [
              Flexible(
                child: Text(
                  title,
                  textAlign: textAlign,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isActiveSortColumn)
                Icon(
                  _sortAscending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              else 
                const SizedBox(width: 16), 
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataTableHeaders() {
    // ... (implementation is the same as previous correct version)
    bool showGradeColumn = isCombinedDivisionEvent;
    int teamNumberFlex = 1;  // Team numbers are short (e.g., "9364A")
    int teamNameFlex = showGradeColumn ? 2 : 3;  // Names need more space
    int orgFlex = showGradeColumn ? 2 : 3;

    // Determine driver/piloting label based on program
    final bool isADC = _selectedProgram == RobotProgram.adc;
    final String driverLabel = isADC ? 'Piloting' : 'Driver';
    final String driverAttemptsLabel = isADC ? 'Piloting Attempts' : 'Driver Attempts';

    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(70),
          borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      child: Row(children: [
        if (_columnVisibility[SortableColumn.teamNumber] ?? true)
          _buildSortableHeader(SortableColumn.teamNumber, 'Team #', teamNumberFlex),
        if (_columnVisibility[SortableColumn.teamName] ?? true)
          _buildSortableHeader(SortableColumn.teamName, 'Team Name', teamNameFlex),
        if (showGradeColumn && (_columnVisibility[SortableColumn.grade] ?? true))
           _buildSortableHeader(SortableColumn.grade, 'Grade', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.organization] ?? true)
          _buildSortableHeader(SortableColumn.organization, 'Organization', orgFlex),
        if (_columnVisibility[SortableColumn.state] ?? true)
          _buildSortableHeader(SortableColumn.state, 'State', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.eligible] ?? true)
          _buildSortableHeader(SortableColumn.eligible, 'Eligible?', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.qualifierRank] ?? true)
          _buildSortableHeader(SortableColumn.qualifierRank, 'Qual', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.skillsRank] ?? true)
          _buildSortableHeader(SortableColumn.skillsRank, 'Skills', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.driverScore] ?? true)
          _buildSortableHeader(SortableColumn.driverScore, driverLabel, 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.pilotAttempts] ?? true)
          _buildSortableHeader(SortableColumn.pilotAttempts, driverAttemptsLabel, 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.programmingScore] ?? true)
          _buildSortableHeader(SortableColumn.programmingScore, 'Auton', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.autonAttempts] ?? true)
          _buildSortableHeader(SortableColumn.autonAttempts, 'Auton Attempts', 1, textAlign: TextAlign.center),
        if (_columnVisibility[SortableColumn.details] ?? true)
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                'Details',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _dataRowWidget(TeamSkills record) {
    // ... (implementation is the same as previous correct version)
    final isEligible = record.eligible;

    // Eligibility-based color (existing logic)
    final Color eligibilityColor = isEligible
        ? Colors.green.withAlpha(40)
        : (record.inRank || record.inSkill ? Colors.orange.withAlpha(30) : Colors.transparent);

    // Manual highlight color (NEW)
    final int colorIndex = _rowColorState[record.team.id] ?? 0;
    final Color manualHighlight = colorIndex > 0
        ? _rowHighlightColors[colorIndex].withAlpha(50)
        : Colors.transparent;

    // Manual highlight takes precedence when set
    final Color rowBgColor = colorIndex > 0 ? manualHighlight : eligibilityColor;

    bool showGradeColumn = isCombinedDivisionEvent;
    int teamNumberFlex = 1;
    int teamNameFlex = showGradeColumn ? 2 : 3;
    int orgFlex = showGradeColumn ? 2 : 3;

    return Material(
      color: rowBgColor,
      child: InkWell(
        onTap: () async {  // NEW: Add tap handler for color cycling
          final int currentIndex = _rowColorState[record.team.id] ?? 0;
          final int nextIndex = (currentIndex + 1) % _rowHighlightColors.length;

          setState(() {
            if (nextIndex == 0) {
              _rowColorState.remove(record.team.id);
            } else {
              _rowColorState[record.team.id] = nextIndex;
            }
          });

          await _saveRowColorState();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(25), width: 0.5))),
          child: Row(children: [
            if (_columnVisibility[SortableColumn.teamNumber] ?? true)
              Expanded(
                flex: teamNumberFlex,
                child: _TableDataCell(
                  record.team.number,
                  isBold: true,
                  color: isEligible ? Colors.lightGreenAccent.shade100 : Colors.white
                )
              ),
            if (_columnVisibility[SortableColumn.teamName] ?? true)
              Expanded(
                flex: teamNameFlex,
                child: Row(
                  children: [
                    Expanded(child: _TableDataCell(record.team.name, fontSize: 12)),
                    if (_teamAwards.containsKey(record.team.id))
                      Tooltip(
                        message: _teamAwards[record.team.id]!,
                        child: Icon(
                          Icons.emoji_events,
                          size: 16,
                          color: Colors.amber.shade300,
                        ),
                      ),
                  ],
                ),
              ),
            if (showGradeColumn && (_columnVisibility[SortableColumn.grade] ?? true))
              Expanded(flex: 1, child: _TableDataCell(record.team.grade.isNotEmpty ? record.team.grade : "N/A", textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.organization] ?? true)
              Expanded(flex: orgFlex, child: _TableDataCell(record.team.organization, fontSize: 12)),
            if (_columnVisibility[SortableColumn.state] ?? true)
              Expanded(flex: 1, child: _TableDataCell(record.team.state, textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.eligible] ?? true)
              Expanded(
                flex: 1,
                child: Icon(
                  isEligible ? Icons.check_circle_outline : Icons.highlight_off_outlined,
                  color: isEligible ? Colors.greenAccent.shade100 : Colors.redAccent.shade100.withAlpha(180),
                  size: 18,
                )
              ),
            if (_columnVisibility[SortableColumn.qualifierRank] ?? true)
              Expanded(flex: 1, child: _TableDataCell(_formatRank(record.qualifierRank),
                  color: record.inRank ? Colors.lightGreenAccent.shade100 : Colors.orangeAccent.shade100,
                  textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.skillsRank] ?? true)
              Expanded(flex: 1, child: _TableDataCell(_formatRank(record.skillsRank),
                  color: record.inSkill ? Colors.lightGreenAccent.shade100 : Colors.orangeAccent.shade100,
                  textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.driverScore] ?? true)
              Expanded(flex: 1, child: _TableDataCell(record.driverScore.toString(), textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.pilotAttempts] ?? true)
              Expanded(flex: 1, child: _TableDataCell(record.driverAttempts.toString(), textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.programmingScore] ?? true)
              Expanded(flex: 1, child: _TableDataCell(record.programmingScore.toString(), textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.autonAttempts] ?? true)
              Expanded(flex: 1, child: _TableDataCell(record.programmingAttempts.toString(), textAlign: TextAlign.center)),
            if (_columnVisibility[SortableColumn.details] ?? true)
              Expanded(
                flex: 1,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.info_outline, size: 18),
                    onPressed: () => _showEligibilityDetailDialog(record),
                    tooltip: 'View Eligibility Details',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
  
  // THIS METHOD WAS MISSING IN THE PREVIOUS RESPONSE - RE-INSERTING IT
  Widget _buildTableForRecordsList(List<TeamSkills> recordsList) {
    if (recordsList.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: Text("No teams match the current filters for this category.")));
    }
    return Card(
      elevation: 2.0, margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        _dataTableHeaders(), // This calls the header builder
        ListView.builder( // This builds the rows
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: recordsList.length,
          itemBuilder: (ctx, i) => _dataRowWidget(recordsList[i]),
        ),
      ]),
    );
  }

  Widget _buildPageContent(List<TeamSkills> processedRecords, {required bool isSearchFilterActive}) {
    // Split records for mobile view
    final List<TeamSkills> eligibleForMobile = processedRecords.where((r) => r.eligible).toList();
    final List<TeamSkills> ineligibleForMobile = processedRecords.where((r) => !r.eligible).toList();

    // Desktop view groupings per grade level
    Map<String, List<TeamSkills>> gradeGroups = {};
    List<TeamSkills> otherTeamsDesktop = [];
    Map<String, String> gradeDisplayNames = {};
    if (!isCombinedDivisionEvent) {
      for (var rec in processedRecords) {
        final grade = rec.team.grade.trim();
        if (grade.isEmpty) {
          otherTeamsDesktop.add(rec);
        } else {
          final lower = grade.toLowerCase();
          gradeGroups.putIfAbsent(lower, () => []).add(rec);
          gradeDisplayNames.putIfAbsent(lower, () => grade);
        }
      }
    } else {
      otherTeamsDesktop = processedRecords;
    }

    List<String> orderedGradeKeys = gradeGroups.keys.toList();
    orderedGradeKeys.sort();
    if (orderedGradeKeys.contains('middle school')) {
      orderedGradeKeys.remove('middle school');
      orderedGradeKeys.insert(0, 'middle school');
    }
    if (orderedGradeKeys.contains('high school')) {
      orderedGradeKeys.remove('high school');
      orderedGradeKeys.insert(orderedGradeKeys.contains('middle school') ? 1 : 0, 'high school');
    }

    if (_isMobileViewEnabled) {
      // Basic error/empty states for mobile
      if (selectedEvent != null && !loading && teams.isEmpty && (error == null || !error!.toLowerCase().contains("team"))) {
        return Center(child: Padding(padding: const EdgeInsets.all(24.0),
            child: Text('No teams data found for event: ${selectedEvent?.name ?? ""}.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)));
      }
      if (selectedEvent != null && !loading && processedRecords.isEmpty && (isSearchFilterActive || hideNoData) && teams.isNotEmpty) {
        return Center(child: Padding(padding: const EdgeInsets.all(24.0),
            child: Text('No teams match current filters.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)));
      }
       if (selectedEvent == null && !loading && events.isEmpty){
         return Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('No recent events found for ${_selectedProgram?.name} in season ${_selectedSeason?.name}.\nTry loading an event by its SKU.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)));
       }
       if (selectedEvent == null && !loading && events.isNotEmpty){
         return Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('Please select an event or load by SKU.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)));
       }
      
      return MobileEligibilityView(
        eligibleRecords: eligibleForMobile,
        ineligibleRecords: ineligibleForMobile,
        selectedProgram: _selectedProgram,
        programRules: _programRules, records: [], // Pass programRules
      );
    }

    // --- Desktop Table View (uses msTeamsDesktop, hsTeamsDesktop, otherTeamsDesktop) ---
    return Column( 
      children: [
        // ... (desktop error and no data messages remain the same, using processedRecords for its isEmpty check)
        if (error != null && selectedEvent != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Card(color: Colors.redAccent.withAlpha(150),
                  child: Padding(padding: const EdgeInsets.all(10.0),
                      child: Text("Error: $error", style: const TextStyle(color: Colors.white))))),
        if (selectedEvent == null && !loading && events.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24.0),
              child: Text('No recent events found for ${_selectedProgram?.name} in season ${_selectedSeason?.name}.\nTry loading an event by its SKU.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
        // ... (other desktop placeholders) ...
        if (selectedEvent != null && !loading && teams.isEmpty && (error == null || !error!.toLowerCase().contains("team")))
          Center(child: Padding(padding: const EdgeInsets.all(24.0),
              child: Text('No teams data found for event: ${selectedEvent?.name ?? ""}. The event might be in the future or data is not yet available.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
        if (selectedEvent != null && !loading && processedRecords.isEmpty && (isSearchFilterActive || hideNoData) && teams.isNotEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24.0),
              child: Text('No teams match current filters.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
        
        if (selectedEvent != null && !loading && (teams.isNotEmpty || (error != null && error!.toLowerCase().contains("team")))) ...[
          if (isCombinedDivisionEvent) ...[
            _tableSectionTitle('All Teams (${otherTeamsDesktop.length})'),
            _buildSummaryWidget(null),
            _buildTableForRecordsList(otherTeamsDesktop),
          ] else ...[
            for (final gradeKey in orderedGradeKeys)
              if (gradeGroups[gradeKey]!.isNotEmpty ||
                  (otherTeamsDesktop.isEmpty && !isSearchFilterActive && !hideNoData &&
                   processedRecords.any((r) => r.team.grade.toLowerCase() == gradeKey))) ...[
                _tableSectionTitle('${gradeDisplayNames[gradeKey]} Teams (${gradeGroups[gradeKey]!.length})'),
                _buildSummaryWidget(gradeDisplayNames[gradeKey]),
                _buildTableForRecordsList(gradeGroups[gradeKey]!),
              ],
            if (otherTeamsDesktop.isNotEmpty) ...[
              _tableSectionTitle('Uncategorized / Grade Not Specified (${otherTeamsDesktop.length})'),
              _buildSummaryWidget(null),
              _buildTableForRecordsList(otherTeamsDesktop),
            ],
          ]
        ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedProgram == null || _selectedSeason == null || (_programRules == null && loading)) {
      return Scaffold(
        appBar: AppBar(title: Text(_selectedProgram?.name ?? 'All-Around Eligibility')),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(), const SizedBox(height: 16),
          Text(error ?? 'Initializing app, please wait...'),
          if (error != null) 
            ElevatedButton.icon(
              icon: const Icon(Icons.settings), 
              label: const Text('Open Settings'), 
              onPressed: _showSettingsDialog
            )
        ])),
      );
    }
    
    List<TeamSkills> processedRecords = tableRecords; 
    
    final String searchTermText = searchCtrl.text.toLowerCase();
    final bool isSearchActive = searchTermText.isNotEmpty;

    if (isSearchActive) {
      processedRecords = processedRecords.where((rec) =>
          rec.team.number.toLowerCase().contains(searchTermText) ||
          rec.team.name.toLowerCase().contains(searchTermText) ||
          rec.team.organization.toLowerCase().contains(searchTermText)).toList();
    }
    if (hideNoData) {
      processedRecords = processedRecords.where((r) =>
          !(r.qualifierRank < 0 && r.skillsRank < 0 && r.driverScore == 0 && r.programmingScore == 0)).toList();
    }
    
    if (_sortColumn != null) {
      processedRecords.sort((a, b) {
        int compareResult = 0;
        switch (_sortColumn!) {
          case SortableColumn.teamNumber:
            compareResult = a.team.number.compareTo(b.team.number);
            break;
          case SortableColumn.teamName:
            compareResult = a.team.name.compareTo(b.team.name);
            break;
          case SortableColumn.grade:
            compareResult = a.team.grade.compareTo(b.team.grade);
            break;
          case SortableColumn.organization:
            compareResult = a.team.organization.compareTo(b.team.organization);
            break;
          case SortableColumn.state:
            compareResult = a.team.state.compareTo(b.team.state);
            break;
          case SortableColumn.eligible:
            compareResult = (a.eligible ? 1 : 0).compareTo(b.eligible ? 1 : 0);
            break;
          case SortableColumn.qualifierRank:
            if (a.qualifierRank == -1 && b.qualifierRank == -1) compareResult = 0;
            else if (a.qualifierRank == -1) compareResult = _sortAscending ? 1 : -1; 
            else if (b.qualifierRank == -1) compareResult = _sortAscending ? -1 : 1;
            else compareResult = a.qualifierRank.compareTo(b.qualifierRank);
            break;
          case SortableColumn.skillsRank:
            if (a.skillsRank == -1 && b.skillsRank == -1) compareResult = 0;
            else if (a.skillsRank == -1) compareResult = _sortAscending ? 1 : -1;
            else if (b.skillsRank == -1) compareResult = _sortAscending ? -1 : 1;
            else compareResult = a.skillsRank.compareTo(b.skillsRank);
            break;
          case SortableColumn.driverScore:
            compareResult = a.driverScore.compareTo(b.driverScore);
            break;
          case SortableColumn.pilotAttempts:
            compareResult = a.driverAttempts.compareTo(b.driverAttempts);
            break;
          case SortableColumn.programmingScore:
            compareResult = a.programmingScore.compareTo(b.programmingScore);
            break;
          case SortableColumn.autonAttempts:
            compareResult = a.programmingAttempts.compareTo(b.programmingAttempts);
            break;
          case SortableColumn.details:
            // Details column is not sortable, no comparison needed
            compareResult = 0;
            break;
        }
        return _sortAscending ? compareResult : -compareResult;
      });
    } else { // Default sort
      processedRecords.sort((a, b) {
        if (a.eligible != b.eligible) return a.eligible ? -1 : 1;
        if (a.qualifierRank > 0 && b.qualifierRank > 0) return a.qualifierRank.compareTo(b.qualifierRank);
        if (a.qualifierRank > 0) return -1;
        if (b.qualifierRank > 0) return 1;
        return a.team.number.compareTo(b.team.number);
      });
    }

    Widget formControls = Form( 
        key: _formKey,
        child: Column(children: [
          Row(children: [
            Expanded(child: TextFormField(
                controller: skuCtrl,
                decoration: InputDecoration(
                    labelText: 'Event SKU (e.g., ${_selectedProgram?.skuPrefix ?? ""}XX-XXXX)',
                    hintText: 'Enter SKU and press Load',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                    prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                    isDense: true),
                validator: (value) => null, 
                onFieldSubmitted: (_) => _loadSku(),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
            const SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: _loadSku, icon: const Icon(Icons.search), label: const Text('Load'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showEventSelectorDialog,
                icon: const Icon(Icons.event, color: Colors.blueAccent),
                label: Text(
                  selectedEvent != null
                      ? '${selectedEvent!.sku} – ${selectedEvent!.name}'
                      : 'Select Recent Event (${_selectedSeason?.name ?? ""})',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  alignment: Alignment.centerLeft,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  side: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
            if (divisions.length > 1) ...[
              const SizedBox(width: 12),
              Expanded(flex: 0, child: DropdownButtonFormField<Division>(
                  decoration: InputDecoration(labelText: 'Division',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)), isDense: true),
                  value: selectedDivision, dropdownColor: Theme.of(context).colorScheme.surface,
                  items: divisions.map((d) => DropdownMenuItem(value: d, child: Text(d.name))).toList(),
                  onChanged: (d) async {
                    if (d != null && selectedEvent != null) {
                      if (!mounted) return;
                      setState(() => selectedDivision = d);
                      await _loadAllDataForEvent(selectedEvent!.id);
                    }
                  },
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
            ]
          ]),
          const SizedBox(height: 12),
          TextFormField(
              controller: searchCtrl,
              decoration: InputDecoration(
                  labelText: 'Filter by Team #, Name, or Org…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                  prefixIcon: const Icon(Icons.filter_alt_outlined, color: Colors.blueAccent),
                  isDense: true,
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { if(mounted) setState(() { searchCtrl.clear(); }); })
                      : null),
              onChanged: (_) { if(mounted) setState(() {}); },
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          SwitchListTile(
              title: const Text("Hide teams with no ranking/skills data", style: TextStyle(fontSize: 13)),
              value: hideNoData, onChanged: (v) { if(mounted) setState(() => hideNoData = v); },
              activeColor: Theme.of(context).colorScheme.secondary, dense: true, contentPadding: EdgeInsets.zero),
          const SizedBox(height: 16),
        ]),
    );

    return KeyboardListener(
      focusNode: _keyFocusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && selectedEvent != null) {
          final bool isControlModifierPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          if (event.logicalKey == LogicalKeyboardKey.f2 || (isControlModifierPressed && event.logicalKey == LogicalKeyboardKey.keyR)) {
            _loadAllDataForEvent(selectedEvent!.id);
          }
        }
      },
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_textScaleFactor),
        ),
        child: Scaffold(
          body: Stack(children: [
          CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 75.0, floating: true, pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                titlePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                title: Text('${_selectedProgram?.awardName ?? 'Eligibility'} - ${_selectedProgram?.name ?? '...'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
                    overflow: TextOverflow.ellipsis),
                background: Container(decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Theme.of(context).colorScheme.primary.withAlpha(220),
                      Theme.of(context).colorScheme.primaryContainer.withAlpha(180)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight))),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.emoji_events_outlined),
                  onPressed: selectedEvent != null && teams.isNotEmpty
                    ? _showAwardAssignmentDialog
                    : null,
                  tooltip: 'Assign Awards',
                  color: Theme.of(context).colorScheme.onPrimary
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: selectedEvent != null ? () => _loadAllDataForEvent(selectedEvent!.id, isAutoReload: true) : null,
                    tooltip: 'Refresh Data (F2 or Ctrl+R)', color: Theme.of(context).colorScheme.onPrimary),
                IconButton(icon: const Icon(Icons.view_column_outlined), onPressed: _showColumnVisibilityDialog,
                    tooltip: 'Show/Hide Columns', color: Theme.of(context).colorScheme.onPrimary),
                IconButton(icon: const Icon(Icons.build), onPressed: _showDevModeDialog,
                    tooltip: 'Dev Mode', color: Theme.of(context).colorScheme.onPrimary),
                IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsDialog,
                    tooltip: 'Settings (Program & Season)', color: Theme.of(context).colorScheme.onPrimary),
              ]),
            SliverPadding(
              padding: const EdgeInsets.all(12.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  formControls, 
                  _buildPageContent(processedRecords, isSearchFilterActive: isSearchActive),
                ]),
              ),
            ),
          ]),
          if (loading && (_selectedProgram != null && _selectedSeason != null))
            Container(
                color: Colors.black.withAlpha((255 * 0.65).round()),
                alignment: Alignment.center,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 16),
                  Text('Loading data...', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                ])),
        ]),
        ),
      ),
    );
  }

  Future<void> _showDevModeDialog() async {
    bool tempForceSplit = _forceSplitExcellence;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(children: [
                Icon(Icons.build, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Dev Mode'),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Force Split Excellence'),
                    subtitle: const Text('Calculate as split grade awards even if the event does not have them'),
                    value: tempForceSplit,
                    onChanged: (val) => setDialogState(() => tempForceSplit = val),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _forceSplitExcellence = tempForceSplit;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSettingsDialog() async {
    // ... (implementation is the same as previous correct version, including Mobile View toggle) ...
    RobotProgram? tempSelectedProgram = _selectedProgram;
    Season? tempSelectedSeason = _selectedSeason;
    List<Season> tempAvailableSeasons = List.from(_availableSeasons);
    bool tempAutoReloadEnabled = _isAutoReloadEnabled;
    bool tempMobileViewEnabled = _isMobileViewEnabled;
    double tempTextScaleFactor = _textScaleFactor;
    Map<RobotProgram, bool> tempProgramEnabled = Map.from(_programEnabled);
    bool dialogIsLoading = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: _selectedProgram != null && _selectedSeason != null,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(builder: (stfContext, setStateDialog) { 
          return AlertDialog(
            title: const Text('App Settings'),
            content: SingleChildScrollView(
              child: dialogIsLoading
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Loading Seasons...")]))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<RobotProgram>(
                          decoration: const InputDecoration(labelText: 'Select Program'),
                          value: tempSelectedProgram,
                          items: RobotProgram.values
                              .where((program) => tempProgramEnabled[program] ?? true)
                              .map((program) =>
                              DropdownMenuItem(value: program, child: Text(program.name))).toList(),
                          onChanged: (program) async {
                            if (program != null) {
                              setStateDialog(() {
                                dialogIsLoading = true;
                                tempSelectedProgram = program;
                                tempSelectedSeason = null; tempAvailableSeasons = [];
                              });
                              try {
                                RobotEventsApiService dialogApi = RobotEventsApiService(program: program, season: Season(id: -1, name: 'temp', programName: 'temp'));
                                List<Season> newSeasons = await dialogApi.fetchSeasons(program.id);
                                newSeasons.sort((a, b) => b.id.compareTo(a.id));
                                if (stfContext.mounted) { 
                                  setStateDialog(() {
                                    tempAvailableSeasons = newSeasons;
                                    tempSelectedSeason = tempAvailableSeasons.isNotEmpty ? tempAvailableSeasons.first : null;
                                    dialogIsLoading = false;
                                  });
                                }
                              } catch (e) {
                                if (stfContext.mounted) { 
                                  setStateDialog(() { dialogIsLoading = false; tempAvailableSeasons = []; tempSelectedSeason = null; });
                                  ScaffoldMessenger.of(stfContext).showSnackBar(SnackBar(
                                      content: Text('Failed to load seasons for ${program.name}: $e'),
                                      backgroundColor: Colors.redAccent));
                                }
                              }
                            }
                          }),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<Season>(
                          decoration: const InputDecoration(labelText: 'Select Season'),
                          value: tempSelectedSeason,
                          isExpanded: true,
                          items: tempAvailableSeasons.map((season) => DropdownMenuItem(
                              value: season, child: Text(season.name, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (season) => setStateDialog(() => tempSelectedSeason = season),
                          hint: tempSelectedProgram == null ? const Text('Select a program first')
                              : (tempAvailableSeasons.isEmpty && !dialogIsLoading ? const Text('No seasons available')
                              : (dialogIsLoading ? const Text("Loading...") : const Text("Select a season"))),
                          disabledHint: dialogIsLoading ? const Text("Loading seasons...") : null,
                          validator: (s) => (s == null && tempSelectedProgram != null && tempAvailableSeasons.isNotEmpty) ? 'Please select a season' : null),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text('Enable Auto-Reload (5 min)'),
                        value: tempAutoReloadEnabled,
                        onChanged: (bool value) {
                          setStateDialog(() {
                            tempAutoReloadEnabled = value;
                          });
                        },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text('Enable Mobile View'),
                        value: tempMobileViewEnabled,
                        onChanged: (bool value) {
                          setStateDialog(() {
                            tempMobileViewEnabled = value;
                          });
                        },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 10),
                      Text('Text Size', style: Theme.of(context).textTheme.bodySmall),
                      Slider(
                        value: tempTextScaleFactor,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        label: "${(tempTextScaleFactor * 100).toStringAsFixed(0)}%",
                        onChanged: (double value) {
                          setStateDialog(() {
                            tempTextScaleFactor = value;
                          });
                        },
                      ),
                    ]),
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    if (_selectedProgram != null && _selectedSeason != null) { 
                        if(dialogContext.mounted) Navigator.of(dialogContext).pop(); 
                    } else { 
                        if (dialogContext.mounted) { 
                           ScaffoldMessenger.of(stfContext).showSnackBar(const SnackBar(
                            content: Text('Please select a program and season to continue.'), backgroundColor: Colors.orangeAccent)); 
                        }
                    }
                  },
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: (tempSelectedProgram != null && tempSelectedSeason != null && !dialogIsLoading)
                      ? () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('selectedProgramId', tempSelectedProgram!.id);
                          await prefs.setInt('selectedSeasonId', tempSelectedSeason!.id);
                          await prefs.setBool(_autoReloadPrefKey, tempAutoReloadEnabled);
                          await prefs.setBool(_mobileViewPrefKey, tempMobileViewEnabled);
                          await prefs.setDouble(_textScalePrefKey, tempTextScaleFactor);

                          bool needsEventReload = _selectedProgram != tempSelectedProgram || _selectedSeason != tempSelectedSeason;
                          bool autoReloadChanged = _isAutoReloadEnabled != tempAutoReloadEnabled;
                          bool mobileViewChanged = _isMobileViewEnabled != tempMobileViewEnabled;
                          bool textSizeChanged = _textScaleFactor != tempTextScaleFactor;

                          if (!mounted) return;
                          setState(() {
                            _selectedProgram = tempSelectedProgram;
                            _programRules = ProgramRules.forProgram(_selectedProgram!);
                            _selectedSeason = tempSelectedSeason;
                            _availableSeasons = tempAvailableSeasons;
                            _isAutoReloadEnabled = tempAutoReloadEnabled;
                            _isMobileViewEnabled = tempMobileViewEnabled;
                            _textScaleFactor = tempTextScaleFactor;
                            api = RobotEventsApiService(program: _selectedProgram!, season: _selectedSeason!);
                            if (needsEventReload) { _clearEventData(resetSort: true); events = []; skuCtrl.clear(); searchCtrl.clear(); selectedEvent=null; }
                          });
                          if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                          
                          if (needsEventReload) {
                            await _loadEvents();
                          } else if (autoReloadChanged || mobileViewChanged || textSizeChanged) {
                            _manageAutoReloadTimer();
                            if(mounted) setState((){});
                          }
                        }
                      : null,
                  child: const Text('Save Settings')),
            ],
          );
        });
      },
    );
  }

  Future<void> _showColumnVisibilityDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Show/Hide Columns'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: SortableColumn.values.map((column) {
                    return CheckboxListTile(
                      title: Text(_getColumnDisplayName(column)),
                      value: _columnVisibility[column] ?? true,
                      onChanged: (bool? newValue) async {
                        if (newValue != null) {
                          setStateDialog(() {
                            _columnVisibility[column] = newValue;
                          });
                          await _saveColumnVisibility();
                          if (mounted) setState(() {});
                        }
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAwardAssignmentDialog() async {
    // Check if awards have been loaded
    if (awards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No awards available for this event yet. Awards may not be finalized.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Assign Awards to Teams'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner: "This only affects this webpage"
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withAlpha(100)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade300, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This only affects this webpage and nothing else. Awards are stored locally.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade100),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Team list with award dropdowns
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setStateDialog) {
                      final sortedTeams = List<Team>.from(teams)
                        ..sort((a, b) => a.number.compareTo(b.number));

                      // Get unique award titles from the awards list
                      final availableAwards = awards.map((a) => a.title).toSet().toList()
                        ..sort();

                      return ListView.builder(
                        itemCount: sortedTeams.length,
                        itemBuilder: (context, index) {
                          final team = sortedTeams[index];
                          final currentAward = _teamAwards[team.id];

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  // Team number and name
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(team.number, style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                                        Text(team.name, style: TextStyle(
                                          fontSize: 11, color: Colors.grey.shade400),
                                          overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Award dropdown
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      value: currentAward,
                                      decoration: InputDecoration(
                                        hintText: 'Select award...',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(6)),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('None', style: TextStyle(fontStyle: FontStyle.italic)),
                                        ),
                                        ...availableAwards.map((award) =>
                                          DropdownMenuItem<String>(
                                            value: award,
                                            child: Text(award, style: const TextStyle(fontSize: 13)),
                                          )
                                        ),
                                      ],
                                      onChanged: (String? newAward) async {
                                        setStateDialog(() {
                                          if (newAward == null) {
                                            _teamAwards.remove(team.id);
                                          } else {
                                            _teamAwards[team.id] = newAward;
                                          }
                                        });
                                        await _saveTeamAwards();
                                        if (mounted) setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEligibilityDetailDialog(TeamSkills record) async {
    final bool isADC = _selectedProgram == RobotProgram.adc;
    final rules = _programRules;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                record.eligible ? Icons.check_circle : Icons.cancel,
                color: record.eligible ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${record.team.number} - ${record.team.name}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Eligibility Status Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: record.eligible
                        ? Colors.green.withAlpha(40)
                        : Colors.red.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: record.eligible ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              record.eligible ? Icons.check_circle : Icons.cancel,
                              color: record.eligible ? Colors.green : Colors.red,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                record.eligible
                                    ? 'ELIGIBLE'
                                    : 'NOT ELIGIBLE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: record.eligible ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For ${_selectedProgram?.awardName ?? "Award"}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Eligibility Requirements Summary
                  Text(
                    'Eligibility Requirements',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRequirementCard(
                    'Qualifier Rank',
                    '${_formatRank(record.qualifierRank)} of ${record.qualifierRankCutoff}',
                    'Must be in top 40% (≤ ${record.qualifierRankCutoff})',
                    record.inRank,
                  ),
                  const SizedBox(height: 8),
                  _buildRequirementCard(
                    'Skills Rank',
                    '${_formatRank(record.skillsRank)} of ${record.skillsRankCutoff}',
                    'Must be in top 40% (≤ ${record.skillsRankCutoff})',
                    record.inSkill,
                  ),
                  const SizedBox(height: 8),
                  if (rules?.requiresProgrammingSkills ?? false)
                    _buildRequirementCard(
                      'Programming Skills',
                      record.programmingScore > 0 ? '${record.programmingScore} points' : 'No score',
                      'Must have a positive programming score',
                      record.programmingScore > 0,
                    ),
                  const SizedBox(height: 8),
                  if (rules?.requiresRankInPositiveProgrammingSkills ?? false)
                    _buildRequirementCard(
                      'Programming-Only Rank',
                      '${_formatRank(record.programmingOnlyRank)} of ${record.programmingOnlyRankCutoff}',
                      'Must be in top 40% of teams with programming scores (≤ ${record.programmingOnlyRankCutoff})',
                      record.meetsProgrammingOnlyRankCriterion,
                    ),
                  const SizedBox(height: 24),

                  // Team Details Section
                  ExpansionTile(
                    title: const Text('Team Information', style: TextStyle(fontWeight: FontWeight.bold)),
                    initiallyExpanded: false,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildDetailRow('Team Number', record.team.number),
                            _buildDetailRow('Team Name', record.team.name),
                            _buildDetailRow('Organization', record.team.organization),
                            _buildDetailRow('Grade', record.team.grade.isNotEmpty ? record.team.grade : 'N/A'),
                            _buildDetailRow('Location', '${record.team.city}, ${record.team.state}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(),

                  // Skills Details Section
                  ExpansionTile(
                    title: const Text('Skills Scores Details', style: TextStyle(fontWeight: FontWeight.bold)),
                    initiallyExpanded: false,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              isADC ? 'Piloting Score' : 'Driver Score',
                              '${record.driverScore} pts (${record.driverAttempts} attempts)',
                            ),
                            _buildDetailRow(
                              'Programming Score',
                              '${record.programmingScore} pts (${record.programmingAttempts} attempts)',
                            ),
                            _buildDetailRow(
                              'Combined Score',
                              '${record.driverScore + record.programmingScore} pts',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRequirementCard(String title, String value, String description, bool met) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: met ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: met ? Colors.green.withAlpha(100) : Colors.red.withAlpha(100),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.cancel,
            color: met ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: met ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool highlight = false, Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? highlightColor : null,
            ),
          ),
        ],
      ),
    );
  }

  String _getColumnDisplayName(SortableColumn column) {
    final bool isADC = _selectedProgram == RobotProgram.adc;
    switch (column) {
      case SortableColumn.teamNumber:
        return 'Team Number';
      case SortableColumn.teamName:
        return 'Team Name';
      case SortableColumn.grade:
        return 'Grade';
      case SortableColumn.organization:
        return 'Organization';
      case SortableColumn.state:
        return 'State';
      case SortableColumn.qualifierRank:
        return 'Qualifier Rank';
      case SortableColumn.skillsRank:
        return 'Skills Rank';
      case SortableColumn.driverScore:
        return isADC ? 'Piloting Score' : 'Driver Score';
      case SortableColumn.programmingScore:
        return 'Programming Score';
      case SortableColumn.eligible:
        return 'Eligible';
      case SortableColumn.pilotAttempts:
        return isADC ? 'Piloting Attempts' : 'Driver Attempts';
      case SortableColumn.autonAttempts:
        return 'Programming Attempts';
      case SortableColumn.details:
        return 'Details';
    }
  }
}

class _TableDataCell extends StatelessWidget {
  final String text;
  final Color? color;
  final bool isBold;
  final TextAlign textAlign;
  final double fontSize;

  const _TableDataCell(this.text, {this.color, this.isBold = false, this.textAlign = TextAlign.left, this.fontSize = 12.0});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Text(text, textAlign: textAlign, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color ?? Theme.of(context).textTheme.bodyMedium?.color, fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)));
}