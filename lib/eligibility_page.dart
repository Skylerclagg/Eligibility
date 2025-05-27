// lib/eligibility_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'models.dart'; // Will use the updated models
import 'mobile_eligibility_view.dart';

enum SortableColumn {
  teamNumber,
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

  bool _isAutoReloadEnabled = false;
  Timer? _autoReloadTimer;
  static const String _autoReloadPrefKey = 'autoReloadEnabled';

  bool _eventHasSplitGradeAwards = false;
  bool _isMobileViewEnabled = false; 
  static const String _mobileViewPrefKey = 'mobileViewEnabled';


  @override
  void initState() {
    super.initState();
    _keyFocusNode = FocusNode();
    _loadInitialSettingsAndData();
  }

  @override
  void dispose() {
    _cancelAutoReloadTimer();
    _keyFocusNode.dispose();
    skuCtrl.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialSettingsAndData() async {
    // ... (implementation is the same)
    if (!mounted) return;
    setState(() { loading = true; error = null; });

    final prefs = await SharedPreferences.getInstance();
    final savedProgramId = prefs.getInt('selectedProgramId');
    final savedSeasonId = prefs.getInt('selectedSeasonId');
    _isAutoReloadEnabled = prefs.getBool(_autoReloadPrefKey) ?? false;
    _isMobileViewEnabled = prefs.getBool(_mobileViewPrefKey) ?? false; 

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
      final all = await api.fetchEvents();
      final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      events = all.where((e) => e.start.isAfter(oneWeekAgo) || e.start.isAtSameMomentAs(oneWeekAgo)).toList();
      events.sort((a, b) => b.start.compareTo(a.start));
    } catch (e) {
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
        if (!events.any((e) => e.id == f.id)) {
          events.insert(0, f);
          events.sort((a, b) => b.start.compareTo(a.start));
        }
        setState(() => selectedEvent = f);
        await _loadAllDataForEvent(f.id); 
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
    setState(() { loading = true; _clearEventData(resetSort: !isAutoReload);});

    try {
      List<Division> fetchedDivisions = await api.fetchDivisions(eventId);
      if (fetchedDivisions.isEmpty) {
        fetchedDivisions.add(Division(id: 1, name: 'Default Division'));
      }
      if (!mounted) return;
      divisions = fetchedDivisions;
      selectedDivision = divisions.first;

      teams = await api.fetchTeams(eventId);
      if (!mounted) return;

      if (selectedDivision != null) {
        rawRankings = await api.fetchRankings(eventId, selectedDivision!.id);
      }
       if (!mounted) return;
      rawSkills = await api.fetchRawSkills(eventId);
       if (!mounted) return;
      awards = await api.fetchAwards(eventId);

      bool detectedSplitAwards = false;
      if (_programRules!.hasMiddleSchoolHighSchoolDivisions) {
          final String baseAwardNameLower = _selectedProgram!.awardName.toLowerCase();
          final String msAwardPattern = "$baseAwardNameLower - middle school";
          final String hsAwardPattern = "$baseAwardNameLower - high school";

          bool msAwardFound = awards.any((awardL) => awardL.title.toLowerCase() == msAwardPattern);
          bool hsAwardFound = awards.any((awardL) => awardL.title.toLowerCase() == hsAwardPattern);

          if (msAwardFound && hsAwardFound) {
              detectedSplitAwards = true;
          }
      }
      if(!mounted) return;
      setState(() {
        _eventHasSplitGradeAwards = detectedSplitAwards;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Failed to load data for event $eventId: $e');
    } finally {
      if (mounted) setState(() => loading = false);
      _manageAutoReloadTimer(); 
    }
  }

  bool get isCombinedDivisionEvent {
    // ... (implementation is the same)
    if (_programRules == null) return true; 
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
            final List<Map<String,dynamic>>? progOnlyPool = gradeProgrammingOnlyRankingsMap["overall_for_prog_rank"];
            if (teamProgrammingScore > 0 && progOnlyPool != null && progOnlyPool.isNotEmpty) {
                final teamEntryInPool = progOnlyPool.firstWhere((e) => e['teamId'] == team.id, orElse: () => {});
                teamProgrammingOnlyRank = teamEntryInPool['rank'] ?? -1;
                programmingOnlyRankCutoffValue = max(1, applyProgramSpecificRounding(progOnlyPool.length * _programRules!.programmingSkillsRankThreshold, _selectedProgram!));
                meetsProgOnlyRankCriterion = teamProgrammingOnlyRank > 0 && teamProgrammingOnlyRank <= programmingOnlyRankCutoffValue;
            } else {
                meetsProgOnlyRankCriterion = false; // No positive score or no pool
            }
        }

      } else { // Grade-specific logic
        final teamGrade = team.grade.toLowerCase();
        String gradeContextKey = teamGrade.isNotEmpty ? teamGrade : "no_grade_for_prog_rank";

        if (teamGrade.isNotEmpty && gradeQualifierRankingsMap.containsKey(teamGrade)) {
            final List<Ranking> gradeQualifiers = gradeQualifierRankingsMap[teamGrade]!;
            final int gradeSpecificQualifierCount = gradeQualifiers.length;
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
            final List<Map<String,dynamic>>? progOnlyPool = gradeProgrammingOnlyRankingsMap[gradeContextKey];
            if (teamProgrammingScore > 0 && progOnlyPool != null && progOnlyPool.isNotEmpty) {
                final teamEntryInPool = progOnlyPool.firstWhere((e) => e['teamId'] == team.id, orElse: () => {});
                teamProgrammingOnlyRank = teamEntryInPool['rank'] ?? -1;
                programmingOnlyRankCutoffValue = max(1, applyProgramSpecificRounding(progOnlyPool.length * _programRules!.programmingSkillsRankThreshold, _selectedProgram!));
                meetsProgOnlyRankCriterion = teamProgrammingOnlyRank > 0 && teamProgrammingOnlyRank <= programmingOnlyRankCutoffValue;
            } else {
                 meetsProgOnlyRankCriterion = false;
            }
        }
      }

      bool isEligible = isInQualifyingRank &&
                        isInSkillsRank &&
                        meetsProgOnlyRankCriterion && // Add new criterion
                        (_programRules!.requiresProgrammingSkills ? (teamProgrammingScore > 0) : true) &&
                        (_programRules!.requiresDriverSkills ? (teamDriverScore > 0) : true);

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
    int teamFlex = showGradeColumn ? 2 : 3; 
    int orgFlex = showGradeColumn ? 2 : 3;   

    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(70),
          borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      child: Row(children: [
        _buildSortableHeader(SortableColumn.teamNumber, 'Team (Num & Name)', teamFlex),
        if (showGradeColumn)
           _buildSortableHeader(SortableColumn.grade, 'Grade', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.organization, 'Organization', orgFlex),
        _buildSortableHeader(SortableColumn.state, 'State', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.eligible, 'Eligible?', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.qualifierRank, 'Qual', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.skillsRank, 'Skills', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.driverScore, 'Pilot', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.pilotAttempts, 'Pilot Attempts', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.programmingScore, 'Auton', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.autonAttempts, 'Auton Attempts', 1, textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _dataRowWidget(TeamSkills record) {
    // ... (implementation is the same as previous correct version)
    final isEligible = record.eligible;
    final Color rowBgColor = isEligible
        ? Colors.green.withAlpha(40)
        : (record.inRank || record.inSkill ? Colors.orange.withAlpha(30) : Colors.transparent);
    bool showGradeColumn = isCombinedDivisionEvent;
    int teamFlex = showGradeColumn ? 2 : 3;
    int orgFlex = showGradeColumn ? 2 : 3;

    return Material(
      color: rowBgColor,
      child: InkWell(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(25), width: 0.5))),
          child: Row(children: [
            Expanded(flex: teamFlex, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TableDataCell(record.team.number,
                      isBold: true,
                      color: isEligible ? Colors.lightGreenAccent.shade100 : Colors.white),
                  Text(record.team.name, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis),
                ])),
            if (showGradeColumn)
              Expanded(flex: 1, child: _TableDataCell(record.team.grade.isNotEmpty ? record.team.grade : "N/A", textAlign: TextAlign.center)),
            Expanded(flex: orgFlex, child: _TableDataCell(record.team.organization, fontSize: 12)),
            Expanded(flex: 1, child: _TableDataCell(record.team.state, textAlign: TextAlign.center)),
            Expanded(
              flex: 1, 
              child: Icon(
                isEligible ? Icons.check_circle_outline : Icons.highlight_off_outlined,
                color: isEligible ? Colors.greenAccent.shade100 : Colors.redAccent.shade100.withAlpha(180),
                size: 18,
              )
            ),
            Expanded(flex: 1, child: _TableDataCell(_formatRank(record.qualifierRank),
                color: record.inRank ? Colors.lightGreenAccent.shade100 : Colors.orangeAccent.shade100,
                textAlign: TextAlign.center)),
            Expanded(flex: 1, child: _TableDataCell(_formatRank(record.skillsRank),
                color: record.inSkill ? Colors.lightGreenAccent.shade100 : Colors.orangeAccent.shade100,
                textAlign: TextAlign.center)),
            Expanded(flex: 1, child: _TableDataCell(record.driverScore.toString(), textAlign: TextAlign.center)),
            Expanded(flex: 1, child: _TableDataCell(record.driverAttempts.toString(), textAlign: TextAlign.center)), 
            Expanded(flex: 1, child: _TableDataCell(record.programmingScore.toString(), textAlign: TextAlign.center)),
            Expanded(flex: 1, child: _TableDataCell(record.programmingAttempts.toString(), textAlign: TextAlign.center)), 
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

    // Desktop view still uses its own msTeams, hsTeams, otherTeams logic for sections
    List<TeamSkills> msTeamsDesktop = [], hsTeamsDesktop = [], otherTeamsDesktop = [];
    if (!isCombinedDivisionEvent) { 
      msTeamsDesktop = processedRecords.where((r) => r.team.grade.toLowerCase() == 'middle school').toList();
      hsTeamsDesktop = processedRecords.where((r) => r.team.grade.toLowerCase() == 'high school' || (r.team.grade.isNotEmpty && r.team.grade.toLowerCase() != 'middle school')).toList();
      otherTeamsDesktop = processedRecords.where((r) => r.team.grade.isEmpty).toList();
    } else {
      otherTeamsDesktop = processedRecords;
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
            // Desktop still shows potentially empty sections if no filters active
            if (msTeamsDesktop.isNotEmpty || (otherTeamsDesktop.isEmpty && hsTeamsDesktop.isEmpty && !isSearchFilterActive && !hideNoData && processedRecords.any((r)=>r.team.grade.toLowerCase()=='middle school'))) ...[
              _tableSectionTitle('Middle School Teams (${msTeamsDesktop.length})'),
              _buildSummaryWidget('Middle School'),
              _buildTableForRecordsList(msTeamsDesktop),
            ],
            if (hsTeamsDesktop.isNotEmpty || (otherTeamsDesktop.isEmpty && msTeamsDesktop.isEmpty && !isSearchFilterActive && !hideNoData && processedRecords.any((r)=>r.team.grade.toLowerCase()=='high school'))) ...[
              _tableSectionTitle('High School / Other Teams (${hsTeamsDesktop.length})'),
               _buildSummaryWidget('High School'),
              _buildTableForRecordsList(hsTeamsDesktop),
            ],
             if (otherTeamsDesktop.isNotEmpty && !isCombinedDivisionEvent) ...[
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
            Expanded(child: DropdownButtonFormField<EventInfo>(
                decoration: InputDecoration(
                    labelText: 'Or Select Recent Event (${_selectedSeason?.name ?? ""})',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                    prefixIcon: const Icon(Icons.event, color: Colors.blueAccent),
                    isDense: true),
                isExpanded: true, value: selectedEvent,
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: events.map((e) {
                  final dateLabel = '${e.start.month}/${e.start.day}/${e.start.year}';
                  return DropdownMenuItem(value: e, child: Text('${e.sku} – ${e.name} ($dateLabel)', overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (e) async {
                  if (e != null) {
                    if (!mounted) return;
                    setState(() { selectedEvent = e; skuCtrl.text = e.sku; });
                    await _loadAllDataForEvent(e.id);
                  }
                },
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
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
                IconButton(icon: const Icon(Icons.refresh), onPressed: selectedEvent != null ? () => _loadAllDataForEvent(selectedEvent!.id) : null,
                    tooltip: 'Refresh Data (F2 or Ctrl+R)', color: Theme.of(context).colorScheme.onPrimary),
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
    );
  }

  Future<void> _showSettingsDialog() async {
    // ... (implementation is the same as previous correct version, including Mobile View toggle) ...
    RobotProgram? tempSelectedProgram = _selectedProgram;
    Season? tempSelectedSeason = _selectedSeason;
    List<Season> tempAvailableSeasons = List.from(_availableSeasons);
    bool tempAutoReloadEnabled = _isAutoReloadEnabled;
    bool tempMobileViewEnabled = _isMobileViewEnabled; 
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
                          items: RobotProgram.values.map((program) =>
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

                          bool needsEventReload = _selectedProgram != tempSelectedProgram || _selectedSeason != tempSelectedSeason;
                          bool autoReloadChanged = _isAutoReloadEnabled != tempAutoReloadEnabled;
                          bool mobileViewChanged = _isMobileViewEnabled != tempMobileViewEnabled;
                          
                          if (!mounted) return;
                          setState(() { 
                            _selectedProgram = tempSelectedProgram;
                            _programRules = ProgramRules.forProgram(_selectedProgram!);
                            _selectedSeason = tempSelectedSeason;
                            _availableSeasons = tempAvailableSeasons;
                            _isAutoReloadEnabled = tempAutoReloadEnabled;
                            _isMobileViewEnabled = tempMobileViewEnabled; 
                            api = RobotEventsApiService(program: _selectedProgram!, season: _selectedSeason!);
                            if (needsEventReload) { _clearEventData(resetSort: true); events = []; skuCtrl.clear(); searchCtrl.clear(); selectedEvent=null; }
                          });
                          if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                          
                          if (needsEventReload) {
                            await _loadEvents();
                          } else if (autoReloadChanged || mobileViewChanged) { 
                            _manageAutoReloadTimer(); 
                            if(mobileViewChanged && mounted) setState((){}); 
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
}

class _TableDataCell extends StatelessWidget {
  // ... (implementation is the same as previous correct version)
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