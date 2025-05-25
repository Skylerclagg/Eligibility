import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'models.dart'; // Ensure your models.dart has the rounding functions

enum SortableColumn {
  teamNumber,
  organization,
  state,
  qualifierRank,
  skillsRank,
  driverScore,
  programmingScore,
  eligible,
  grade, // Added Grade
}

class EligibilityPage extends StatefulWidget {
  const EligibilityPage({super.key});
  @override
  State<EligibilityPage> createState() => _EligibilityPageState();
}

class _EligibilityPageState extends State<EligibilityPage> {
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
    if (!mounted) return;
    setState(() { loading = true; error = null; });

    final prefs = await SharedPreferences.getInstance();
    final savedProgramId = prefs.getInt('selectedProgramId');
    final savedSeasonId = prefs.getInt('selectedSeasonId');
    _isAutoReloadEnabled = prefs.getBool(_autoReloadPrefKey) ?? false;

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
        _programRules = ProgramRules.forProgram(_selectedProgram!);
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
    _autoReloadTimer?.cancel();
    _autoReloadTimer = null;
  }

  Future<void> _loadEvents() async {
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
    if (_programRules == null) return true; 
    if (!_programRules!.hasMiddleSchoolHighSchoolDivisions) {
      return true;
    }
    return !_eventHasSplitGradeAwards;
  }

  double get eligibilityThreshold {
    if (_programRules == null) return 0.5;
    return _programRules!.threshold;
  }

  Map<int, RawSkill> getConsolidatedSkills() {
    final Map<int, RawSkill> consolidated = {};
    for (var skillRun in rawSkills) {
      consolidated.update(
        skillRun.teamId,
        (existing) => RawSkill(
          teamId: skillRun.teamId,
          rank: (skillRun.rank > 0 && (existing.rank <= 0 || skillRun.rank < existing.rank)) ? skillRun.rank : existing.rank,
          programmingScore: existing.programmingScore + skillRun.programmingScore,
          driverScore: existing.driverScore + skillRun.driverScore,
        ),
        ifAbsent: () => skillRun,
      );
    }
    return consolidated;
  }

  List<TeamSkills> get tableRecords {
    if (_programRules == null || teams.isEmpty || _selectedProgram == null) return [];

    final Map<int, RawSkill> currentConsolidatedSkills = getConsolidatedSkills();
    final Map<int, Team> teamMap = {for (var t in teams) t.id: t};

    Map<String, List<Ranking>> gradeQualifierRankingsMap = {};
    Map<String, List<RawSkill>> gradeSkillsRankingsMap = {};

    // Use the getter, which now considers _eventHasSplitGradeAwards
    if (!isCombinedDivisionEvent) { 
      final Set<String> grades = teams.map((t) => t.grade.toLowerCase()).toSet()..removeWhere((g) => g.isEmpty);
      for (String grade in grades) {
        gradeQualifierRankingsMap[grade] = rawRankings
            .where((r) {
              final rTeam = teamMap[r.teamId];
              return rTeam != null && rTeam.grade.toLowerCase() == grade && r.rank > 0;
            })
            .toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));

        gradeSkillsRankingsMap[grade] = currentConsolidatedSkills.values
            .where((s) {
              final sTeam = teamMap[s.teamId];
              return sTeam != null && sTeam.grade.toLowerCase() == grade && s.rank > 0;
            })
            .toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
      }
    }

    return teams.map((team) {
      final skillsData = currentConsolidatedSkills[team.id];
      final overallRankingData = rawRankings.firstWhere((r) => r.teamId == team.id,
          orElse: () => Ranking(teamId: team.id, rank: -1));

      int displayQualRank = overallRankingData.rank > 0 ? overallRankingData.rank : -1;
      int displaySkillsRank = -1;
      
      if(skillsData != null && skillsData.rank > 0){
          final overallSortedSkills = currentConsolidatedSkills.values.where((s) => s.rank > 0).toList()..sort((a,b)=>a.rank.compareTo(b.rank));
          displaySkillsRank = overallSortedSkills.indexWhere((s) => s.teamId == team.id) + 1;
          if(displaySkillsRank == 0) displaySkillsRank = -1;
      }

      bool isInQualifyingRank;
      bool isInSkillsRank;
      int qualCutoff;
      int skillsCutoffTargetRank; 

      if (isCombinedDivisionEvent) { 
        final totalRankedTeamsInDivision = rawRankings.where((r) => r.rank > 0).length;
        qualCutoff = max(1, applyProgramSpecificRounding(totalRankedTeamsInDivision * eligibilityThreshold, _selectedProgram!));
        isInQualifyingRank = displayQualRank > 0 && displayQualRank <= qualCutoff;

        skillsCutoffTargetRank = max(1, applyProgramSpecificRounding(totalRankedTeamsInDivision * eligibilityThreshold, _selectedProgram!));
        isInSkillsRank = displaySkillsRank > 0 && displaySkillsRank <= skillsCutoffTargetRank;
      } else { 
        final teamGrade = team.grade.toLowerCase();
        if (teamGrade.isNotEmpty && gradeQualifierRankingsMap.containsKey(teamGrade)) {
            final List<Ranking> gradeQualifiers = gradeQualifierRankingsMap[teamGrade]!;
            final int gradeSpecificQualifierCount = gradeQualifiers.length;
            qualCutoff = max(1, applyProgramSpecificRounding(gradeSpecificQualifierCount * eligibilityThreshold, _selectedProgram!));
            
            final teamIndexInGradeQual = gradeQualifiers.indexWhere((r) => r.teamId == team.id);
            displayQualRank = (teamIndexInGradeQual != -1) ? teamIndexInGradeQual + 1 : -1;
            isInQualifyingRank = displayQualRank > 0 && displayQualRank <= qualCutoff;

            final List<RawSkill> gradeSkills = gradeSkillsRankingsMap[teamGrade]!;
            skillsCutoffTargetRank = max(1, applyProgramSpecificRounding(gradeSpecificQualifierCount * eligibilityThreshold, _selectedProgram!));
            
            final teamIndexInGradeSkills = gradeSkills.indexWhere((s) => s.teamId == team.id);
            displaySkillsRank = (teamIndexInGradeSkills != -1) ? teamIndexInGradeSkills + 1 : -1;
            isInSkillsRank = displaySkillsRank > 0 && displaySkillsRank <= skillsCutoffTargetRank;
        } else { 
            isInQualifyingRank = false;
            isInSkillsRank = false;
            displayQualRank = overallRankingData.rank > 0 ? overallRankingData.rank : -1;
        }
      }

      final bool hasProg = (skillsData?.programmingScore ?? 0) > 0;
      final bool hasDriver = (skillsData?.driverScore ?? 0) > 0;

      bool isEligible = isInQualifyingRank &&
                        isInSkillsRank &&
                        (_programRules!.requiresProgrammingSkills ? hasProg : true) &&
                        (_programRules!.requiresDriverSkills ? hasDriver : true);

      return TeamSkills(
        team: team,
        qualifierRank: displayQualRank,
        skillsRank: displaySkillsRank,
        programmingScore: skillsData?.programmingScore ?? 0,
        driverScore: skillsData?.driverScore ?? 0,
        eligible: isEligible,
        inRank: isInQualifyingRank,
        inSkill: isInSkillsRank,
      );
    }).toList();
  }

  String _formatRank(int rank) => rank < 0 ? 'N/A' : '#$rank';

  Widget _buildSummaryWidget(String? gradeLevelContext) {
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
            orElse: () => Team(id: -1, number: '', name: '', grade: '', organization: '', state: ''));
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
            Text('Skills Rank Cutoff (Top ${(eligibilityThreshold * 100).toStringAsFixed(0)}% of ${gradeLevelContext ?? ""} teams): ≤#$skillsCutoffRankDisplay'.replaceFirst(" qualifier teams", gradeLevelContext !=null ? " $gradeLevelContext qualifier teams" : " qualifier teams"),
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
    bool showGradeColumn = isCombinedDivisionEvent; // Determine if grade column should be shown

    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(70),
          borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      child: Row(children: [
        _buildSortableHeader(SortableColumn.teamNumber, 'Team (Num & Name)', showGradeColumn ? 2 : 3), // Adjust flex
        if (showGradeColumn)
           _buildSortableHeader(SortableColumn.grade, 'Grade', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.organization, 'Organization', showGradeColumn ? 2 : 3), // Adjust flex
        _buildSortableHeader(SortableColumn.state, 'State', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.eligible, 'Eligible?', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.qualifierRank, 'Qual', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.skillsRank, 'Skills', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.driverScore, 'Pilot', 1, textAlign: TextAlign.center),
        _buildSortableHeader(SortableColumn.programmingScore, 'Auton', 1, textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _dataRowWidget(TeamSkills record) {
    final isEligible = record.eligible;
    final Color rowBgColor = isEligible
        ? Colors.green.withAlpha(40)
        : (record.inRank || record.inSkill ? Colors.orange.withAlpha(30) : Colors.transparent);
    bool showGradeColumn = isCombinedDivisionEvent;

    return Material(
      color: rowBgColor,
      child: InkWell(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(25), width: 0.5))),
          child: Row(children: [
            Expanded(flex: showGradeColumn ? 2 : 3, child: Column( // Adjust flex
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TableDataCell(record.team.number,
                      isBold: true,
                      color: isEligible ? Colors.lightGreenAccent.shade100 : Colors.white),
                  Text(record.team.name, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis),
                ])),
            if (showGradeColumn)
              Expanded(flex: 1, child: _TableDataCell(record.team.grade.isNotEmpty ? record.team.grade : "N/A", textAlign: TextAlign.center)),
            Expanded(flex: showGradeColumn ? 2 : 3, child: _TableDataCell(record.team.organization, fontSize: 12)), // Adjust flex
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
            Expanded(flex: 1, child: _TableDataCell(record.programmingScore.toString(), textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
  }
  
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
        _dataTableHeaders(),
        ListView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: recordsList.length,
          itemBuilder: (ctx, i) => _dataRowWidget(recordsList[i]),
        ),
      ]),
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
    
    final String searchTerm = searchCtrl.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      processedRecords = processedRecords.where((rec) =>
          rec.team.number.toLowerCase().contains(searchTerm) ||
          rec.team.name.toLowerCase().contains(searchTerm) ||
          rec.team.organization.toLowerCase().contains(searchTerm)).toList();
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
          case SortableColumn.grade: // Added sort case for Grade
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
          case SortableColumn.programmingScore:
            compareResult = a.programmingScore.compareTo(b.programmingScore);
            break;
        }
        return _sortAscending ? compareResult : -compareResult;
      });
    } else {
      processedRecords.sort((a, b) {
        if (a.eligible != b.eligible) return a.eligible ? -1 : 1;
        if (a.qualifierRank > 0 && b.qualifierRank > 0) return a.qualifierRank.compareTo(b.qualifierRank);
        if (a.qualifierRank > 0) return -1;
        if (b.qualifierRank > 0) return 1;
        return a.team.number.compareTo(b.team.number);
      });
    }

    List<TeamSkills> msTeams = [], hsTeams = [], otherTeams = [];
    // Use the getter isCombinedDivisionEvent to determine list population
    if (!isCombinedDivisionEvent) { 
      msTeams = processedRecords.where((r) => r.team.grade.toLowerCase() == 'middle school').toList();
      hsTeams = processedRecords.where((r) => r.team.grade.toLowerCase() == 'high school' || (r.team.grade.isNotEmpty && r.team.grade.toLowerCase() != 'middle school')).toList();
      otherTeams = processedRecords.where((r) => r.team.grade.isEmpty).toList();
    } else {
      otherTeams = processedRecords; // For combined events, all go into otherTeams for single table display
    }

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
              sliver: SliverList(delegate: SliverChildListDelegate([
                Form(key: _formKey, child: Column(children: [
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
                ])),
                if (error != null && selectedEvent != null)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Card(color: Colors.redAccent.withAlpha(150),
                          child: Padding(padding: const EdgeInsets.all(10.0),
                              child: Text("Error: $error", style: const TextStyle(color: Colors.white))))),
                if (selectedEvent == null && !loading && events.isEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('No recent events found for ${_selectedProgram?.name} in season ${_selectedSeason?.name}.\nTry loading an event by its SKU.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
                if (selectedEvent == null && !loading && events.isNotEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('Please select an event or load by SKU.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
                if (selectedEvent != null && !loading && teams.isEmpty && (error == null || !error!.toLowerCase().contains("team")))
                  Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('No teams data found for event: ${selectedEvent?.name ?? ""}. The event might be in the future or data is not yet available.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
                if (selectedEvent != null && !loading && processedRecords.isEmpty && (searchCtrl.text.isNotEmpty || hideNoData) && teams.isNotEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(24.0),
                      child: Text('No teams match current filters.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge))),
                
                if (selectedEvent != null && !loading && (teams.isNotEmpty || (error != null && error!.toLowerCase().contains("team")))) ...[
                  if (isCombinedDivisionEvent) ...[
                    _tableSectionTitle('All Teams (${otherTeams.length})'),
                    _buildSummaryWidget(null),
                    _buildTableForRecordsList(otherTeams),
                  ] else ...[
                    if (msTeams.isNotEmpty || (otherTeams.isEmpty && hsTeams.isEmpty && searchTerm.isEmpty && !hideNoData && processedRecords.any((r)=>r.team.grade.toLowerCase()=='middle school'))) ...[
                      _tableSectionTitle('Middle School Teams (${msTeams.length})'),
                      _buildSummaryWidget('Middle School'),
                      _buildTableForRecordsList(msTeams),
                    ],
                    if (hsTeams.isNotEmpty || (otherTeams.isEmpty && msTeams.isEmpty && searchTerm.isEmpty && !hideNoData && processedRecords.any((r)=>r.team.grade.toLowerCase()=='high school'))) ...[
                      _tableSectionTitle('High School / Other Teams (${hsTeams.length})'),
                       _buildSummaryWidget('High School'),
                      _buildTableForRecordsList(hsTeams),
                    ],
                     if (otherTeams.isNotEmpty && !isCombinedDivisionEvent) ...[
                      _tableSectionTitle('Uncategorized / Grade Not Specified (${otherTeams.length})'),
                       _buildSummaryWidget(null), 
                      _buildTableForRecordsList(otherTeams),
                    ],
                  ]
                ]
              ])),
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
    RobotProgram? tempSelectedProgram = _selectedProgram;
    Season? tempSelectedSeason = _selectedSeason;
    List<Season> tempAvailableSeasons = List.from(_availableSeasons);
    bool tempAutoReloadEnabled = _isAutoReloadEnabled;
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

                          bool needsEventReload = _selectedProgram != tempSelectedProgram || _selectedSeason != tempSelectedSeason;
                          bool autoReloadChanged = _isAutoReloadEnabled != tempAutoReloadEnabled;
                          
                          if (!mounted) return;
                          setState(() { 
                            _selectedProgram = tempSelectedProgram;
                            _programRules = ProgramRules.forProgram(_selectedProgram!);
                            _selectedSeason = tempSelectedSeason;
                            _availableSeasons = tempAvailableSeasons;
                            _isAutoReloadEnabled = tempAutoReloadEnabled;
                            api = RobotEventsApiService(program: _selectedProgram!, season: _selectedSeason!);
                            if (needsEventReload) { _clearEventData(resetSort: true); events = []; skuCtrl.clear(); searchCtrl.clear(); selectedEvent=null; }
                          });
                          if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                          
                          if (needsEventReload) {
                            await _loadEvents();
                          } else if (autoReloadChanged) {
                            _manageAutoReloadTimer();
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