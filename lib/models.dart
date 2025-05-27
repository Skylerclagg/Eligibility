import 'dart:math';

// --- Rounding Helper Functions --- (remain the same)
int roundHalfUp(double value) {
  return value.round();
}

int roundHalfToEven(double value) {
  assert(value >= 0, "This rounding function is intended for non-negative cutoff values.");
  double fraction = value - value.floor();
  if (fraction == 0.5) {
    if (value.floor().isEven) {
      return value.floor();
    } else {
      return value.ceil();
    }
  }
  return value.round();
}

int applyProgramSpecificRounding(double calculatedValue, RobotProgram program) {
  if (program == RobotProgram.adc) {
    return roundHalfToEven(calculatedValue);
  } else {
    return roundHalfUp(calculatedValue);
  }
}
// --- End Rounding Helper Functions ---

enum RobotProgram { 
  v5rc(id: 1, name: 'V5RC', skuPrefix: 'RE-V5RC-', awardName: 'Excellence Award'),
  viqrc(id: 41, name: 'VIQRC', skuPrefix: 'RE-VIQRC-', awardName: 'Excellence Award'),
  vurc(id: 4, name: 'VURC', skuPrefix: 'RE-VURC-', awardName: 'Excellence Award'),
  adc(id: 44, name: 'ADC', skuPrefix: 'RE-ADC-', awardName: 'All-Around Champion');

  final int id;
  final String name;
  final String skuPrefix;
  final String awardName;

  const RobotProgram({
    required this.id,
    required this.name,
    required this.skuPrefix,
    required this.awardName,
  });
}

class ProgramRules {
  final double threshold; 
  final bool requiresDriverSkills;
  final bool requiresProgrammingSkills; 
  final bool hasMiddleSchoolHighSchoolDivisions;

  final bool requiresRankInPositiveProgrammingSkills; 
  final double programmingSkillsRankThreshold; 

  const ProgramRules({
    this.threshold = 0.5,
    this.requiresDriverSkills = true,
    this.requiresProgrammingSkills = true, 
    this.hasMiddleSchoolHighSchoolDivisions = false,
    this.requiresRankInPositiveProgrammingSkills = false, 
    this.programmingSkillsRankThreshold = 0.4,      
  });

  factory ProgramRules.forProgram(RobotProgram program) {
    switch (program) {
      case RobotProgram.v5rc:
        return const ProgramRules(
          threshold: 0.40, // Assuming main threshold is now 40%
          requiresDriverSkills: true,
          requiresProgrammingSkills: true, // Still need a prog score (e.g. > 0 for skills)
          hasMiddleSchoolHighSchoolDivisions: true,
          requiresRankInPositiveProgrammingSkills: true, 
          programmingSkillsRankThreshold: 0.40,        
        );
      case RobotProgram.viqrc:
        return const ProgramRules(
          threshold: 0.40, // Assuming main threshold is now 40%
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: true,
          requiresRankInPositiveProgrammingSkills: true, 
          programmingSkillsRankThreshold: 0.40,        
        );
      case RobotProgram.vurc:
        return const ProgramRules(
          threshold: 0.40, // Assuming main threshold is now 40%
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: false,
          requiresRankInPositiveProgrammingSkills: true, 
          programmingSkillsRankThreshold: 0.40,        
        );
      case RobotProgram.adc:
        return const ProgramRules(
          threshold: 0.50, 
          requiresDriverSkills: false, 
          requiresProgrammingSkills: true, 
          hasMiddleSchoolHighSchoolDivisions: false,
          requiresRankInPositiveProgrammingSkills: false, // ADC does not use this new specific rule
          programmingSkillsRankThreshold: 0.4, // Default, but unused if above is false
        );
    }
  }
}

class Season { /* ... remains the same ... */ 
  final int id;
  final String name;
  final String programName;

  Season({required this.id, required this.name, required this.programName});

  factory Season.fromJson(Map<String, dynamic> j) => Season(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        programName: (j['program'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) => other is Season && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Ranking { /* ... remains the same ... */ 
  final int teamId;
  final int rank;

  Ranking({required this.teamId, required this.rank});

  factory Ranking.fromJson(Map<String, dynamic> j) => Ranking(
        teamId: (j['team'] as Map<String, dynamic>)['id'] as int,
        rank: j['rank'] as int? ?? -1,
      );
}

class EventInfo { /* ... remains the same ... */
  final int id;
  final String sku;
  final String name;
  final DateTime start;

  EventInfo({
    required this.id,
    required this.sku,
    required this.name,
    required this.start,
  });

  factory EventInfo.fromJson(Map<String, dynamic> j) => EventInfo(
        id: j['id'] as int,
        sku: j['sku'] as String? ?? '',
        name: j['name'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
      );

  @override
  bool operator ==(Object other) => other is EventInfo && other.id == id && other.sku == sku;
  @override
  int get hashCode => id.hashCode;
}

class Division { /* ... remains the same ... */
  final int id;
  final String name;
  Division({required this.id, required this.name});
  factory Division.fromJson(Map<String, dynamic> j) => Division(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
      );
}

class Team { /* ... remains the same with city, state, country ... */
  final int id;
  final String number;
  final String name;
  final String grade;
  final String organization;
  final String city;
  final String state; 
  final String country;

  Team({
    required this.id,
    required this.number,
    required this.name,
    required this.grade,
    required this.organization,
    required this.city,
    required this.state,
    required this.country,
  });

  factory Team.fromJson(Map<String, dynamic> j) {
    final location = j['location'] as Map<String, dynamic>?;
    return Team(
      id: j['id'] as int,
      number: j['number'] as String? ?? '',
      name: j['team_name'] as String? ?? j['name'] as String? ?? '',
      grade: j['grade'] as String? ?? '',
      organization: j['organization'] as String? ?? '',
      city: location?['city'] as String? ?? '',
      state: location?['region'] as String? ?? '',
      country: location?['country'] as String? ?? '',
    );
  }
}

class RawSkill { /* ... remains the same, includes attempts ... */
  final int teamId;
  final String type; 
  final int rank;
  final int score;
  final int attempts; 

  RawSkill({
    required this.teamId,
    required this.type,
    required this.rank,
    required this.score,
    required this.attempts, 
  });

  int get programmingScore => type == 'programming' ? score : 0;
  int get driverScore => type == 'driver' ? score : 0;

  factory RawSkill.fromJson(Map<String, dynamic> j) {
    return RawSkill(
      teamId: (j['team'] as Map<String, dynamic>)['id'] as int,
      type: j['type'] as String? ?? '',
      rank: (j['rank'] as int?) ?? -1,
      score: (j['score'] as int?) ?? 0,
      attempts: (j['attempts'] as int?) ?? 0, 
    );
  }
}

class Award { /* ... remains the same ... */
  final String title;
  Award({required this.title});
  factory Award.fromJson(Map<String, dynamic> j) =>
      Award(title: j['title'] as String? ?? '');
}

class TeamSkills {
  final Team team;
  final int qualifierRank;
  final int skillsRank; 
  final int programmingScore;
  final int driverScore;
  final int programmingAttempts;
  final int driverAttempts;    
  final bool eligible;
  final bool inRank;
  final bool inSkill; 
  final int qualifierRankCutoff; 
  final int skillsRankCutoff;   

  // New fields for specific programming skills ranking criterion
  final int programmingOnlyRank;
  final int programmingOnlyRankCutoff;
  final bool meetsProgrammingOnlyRankCriterion;

  TeamSkills({
    required this.team,
    required this.qualifierRank,
    required this.skillsRank,
    required this.programmingScore,
    required this.driverScore,
    required this.programmingAttempts,
    required this.driverAttempts,    
    required this.eligible,
    required this.inRank,
    required this.inSkill,
    required this.qualifierRankCutoff, 
    required this.skillsRankCutoff,
    required this.programmingOnlyRank,
    required this.programmingOnlyRankCutoff,
    required this.meetsProgrammingOnlyRankCriterion,
  });
}