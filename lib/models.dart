

// --- Rounding Helper Functions ---
// Standard round half up (for positive numbers, Dart's .round() does this)
int roundHalfUp(double value) {
  return value.round();
}

// Banker's rounding / round half to even (for non-negative values)
int roundHalfToEven(double value) {
  assert(value >= 0, "This rounding function is intended for non-negative cutoff values.");
  double fraction = value - value.floor();
  if (fraction == 0.5) {
    if (value.floor().isEven) {
      return value.floor(); // e.g., 2.5 -> 2
    } else {
      return value.ceil();  // e.g., 3.5 -> 4
    }
  }
  return value.round(); // Standard rounding for other fractions
}

// Applies the correct rounding based on the program
int applyProgramSpecificRounding(double calculatedValue, RobotProgram program) {
  if (program == RobotProgram.adc) {
    return roundHalfToEven(calculatedValue);
  } else {
    return roundHalfUp(calculatedValue);
  }
}
// --- End Rounding Helper Functions ---

enum RobotProgram {
  v5rc(id: 1, name: 'V5RC - VEX Robotics Competition', skuPrefix: 'RE-V5RC-', awardName: 'Excellence Award'),
  viqrc(id: 41, name: 'VIQRC - VEX IQ Robotics Competition', skuPrefix: 'RE-VIQRC-', awardName: 'Excellence Award'),
  vurc(id: 4, name: 'VURC - VEX U Robotics Competition', skuPrefix: 'RE-VURC-', awardName: 'Excellence Award'),
  adc(id: 44, name: 'ADC - Aerial Drone Competition', skuPrefix: 'RE-ADC-', awardName: 'All-Around Champion');

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

  const ProgramRules({
    this.threshold = 0.5,
    this.requiresDriverSkills = true,
    this.requiresProgrammingSkills = true,
    this.hasMiddleSchoolHighSchoolDivisions = false,
  });

  factory ProgramRules.forProgram(RobotProgram program) {
    switch (program) {
      case RobotProgram.v5rc:
        return const ProgramRules(
          threshold: 0.4,
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: true,
        );
      case RobotProgram.viqrc:
        return const ProgramRules(
          threshold: 0.4,
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: true,
        );
      case RobotProgram.vurc:
        return const ProgramRules(
          threshold: 0.4,
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: false,
        );
      case RobotProgram.adc:
        return const ProgramRules(
          threshold: 0.5,
          requiresDriverSkills: true,
          requiresProgrammingSkills: true,
          hasMiddleSchoolHighSchoolDivisions: true,
        );
    }
  }
}

class Season {
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

class Ranking {
  final int teamId;
  final int rank;

  Ranking({required this.teamId, required this.rank});

  factory Ranking.fromJson(Map<String, dynamic> j) => Ranking(
        teamId: (j['team'] as Map<String, dynamic>)['id'] as int,
        rank: j['rank'] as int? ?? -1,
      );
}

class EventInfo {
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

class Division {
  final int id;
  final String name;
  Division({required this.id, required this.name});
  factory Division.fromJson(Map<String, dynamic> j) => Division(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
      );
}

class Team {
  final int id;
  final String number;
  final String name;
  final String grade;
  final String organization;
  final String state;

  Team({
    required this.id,
    required this.number,
    required this.name,
    required this.grade,
    required this.organization,
    required this.state,
  });

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as int,
        number: j['number'] as String? ?? '',
        name: j['team_name'] as String? ?? '',
        grade: j['grade'] as String? ?? '',
        organization: j['organization'] as String? ?? '',
        state: (j['location'] as Map<String, dynamic>?)?['region'] as String? ?? '',
      );
}

class RawSkill {
  final int teamId;
  final int rank;
  final int programmingScore;
  final int driverScore;
  RawSkill({
    required this.teamId,
    required this.rank,
    required this.programmingScore,
    required this.driverScore,
  });
  factory RawSkill.fromJson(Map<String, dynamic> j) {
    final tid = (j['team'] as Map<String, dynamic>)['id'] as int;
    final type = j['type'] as String? ?? '';
    final score = (j['score'] as int?) ?? 0;
    return RawSkill(
      teamId: tid,
      rank: (j['rank'] as int?) ?? -1,
      programmingScore: type == 'programming' ? score : 0,
      driverScore: type == 'driver' ? score : 0,
    );
  }
}

class Award {
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
  final bool eligible;
  final bool inRank;
  final bool inSkill;
  TeamSkills({
    required this.team,
    required this.qualifierRank,
    required this.skillsRank,
    required this.programmingScore,
    required this.driverScore,
    required this.eligible,
    required this.inRank,
    required this.inSkill,
  });
}