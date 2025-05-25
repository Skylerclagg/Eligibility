// lib/team_eligibility_detail_page.dart
import 'package:flutter/material.dart';
import 'models.dart'; // Assuming models.dart is in the lib folder

class TeamEligibilityDetailPage extends StatelessWidget {
  final TeamSkills teamSkills;
  final RobotProgram selectedProgram;
  final ProgramRules programRules;
  // To display cutoffs, we either need to pass them or TeamSkills needs to store them.
  // For now, we'll rely on inRank/inSkill flags for coloring.
  // final int qualifierCutoff; 
  // final int skillsCutoff;

  const TeamEligibilityDetailPage({
    super.key,
    required this.teamSkills,
    required this.selectedProgram,
    required this.programRules,
    // required this.qualifierCutoff,
    // required this.skillsCutoff,
  });

  Widget _buildDetailRow(BuildContext context, String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ", style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              value, 
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: isBold ? FontWeight.bold : null
              )
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final team = teamSkills.team;
    final bool isADC = selectedProgram == RobotProgram.adc;
    final String progLabel = isADC ? "Autonomous Flight" : "Programming";
    final String driverLabel = isADC ? "Piloting" : "Driver";

    List<String> ineligibleReasons = [];
    if (!teamSkills.eligible) {
      if (!teamSkills.inRank) {
        ineligibleReasons.add(teamSkills.qualifierRank > 0 
            ? "Qualifier Rank (#${teamSkills.qualifierRank}) Cutoff is (#${teamSkills.qualifierRankCutoff})." 
            : "No qualifying rank or not in cutoff.");
      }
      if (!teamSkills.inSkill) {
        ineligibleReasons.add(teamSkills.skillsRank > 0
            ? "Skills Rank (#${teamSkills.skillsRank})  Cutoff is (#${teamSkills.skillsRankCutoff})."
            : "No skills rank or not in cutoff.");
      }
      if (programRules.requiresProgrammingSkills && teamSkills.programmingScore <= 0) {
        ineligibleReasons.add("$progLabel Score not > 0 (Score: ${teamSkills.programmingScore})");
      }
      if (programRules.requiresDriverSkills && teamSkills.driverScore <= 0) {
        ineligibleReasons.add("$driverLabel Score not > 0 (Score: ${teamSkills.driverScore})");
      }
      if (ineligibleReasons.isEmpty && !teamSkills.eligible) {
        ineligibleReasons.add("Other criteria not met."); // Fallback
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Team ${team.number} Details"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${team.number} - ${team.name}", style: Theme.of(context).textTheme.headlineSmall),
            if (team.organization.isNotEmpty) Text(team.organization, style: Theme.of(context).textTheme.titleMedium),
            Text("Grade: ${team.grade.isNotEmpty ? team.grade : 'N/A'} | State: ${team.state.isNotEmpty ? team.state : 'N/A'}", style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Text(
              teamSkills.eligible ? "ELIGIBLE for ${selectedProgram.awardName}" : "NOT ELIGIBLE for ${selectedProgram.awardName}",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: teamSkills.eligible ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 20),

            Text("Ranking & Skills Status:", style: Theme.of(context).textTheme.titleMedium),
            _buildDetailRow(context, "Qualifier Rank", teamSkills.qualifierRank > 0 ? "#${teamSkills.qualifierRank}" : "N/A", 
                          valueColor: teamSkills.inRank ? Colors.green.shade700 : (teamSkills.qualifierRank > 0 ? Colors.red.shade700 : null)),
            // To show actual cutoff, it needs to be passed or stored in TeamSkills
            // _buildDetailRow(context, "Qualifier Cutoff", "≤#$qualifierCutoff"), 
            _buildDetailRow(context, "Skills Rank", teamSkills.skillsRank > 0 ? "#${teamSkills.skillsRank}" : "N/A",
                          valueColor: teamSkills.inSkill ? Colors.green.shade700 : (teamSkills.skillsRank > 0 ? Colors.red.shade700 : null)),
            // _buildDetailRow(context, "Skills Cutoff", "≤#$skillsCutoff"),
            
            const Divider(height: 20),
            Text("$progLabel Skills:", style: Theme.of(context).textTheme.titleMedium),
            _buildDetailRow(context, "Score", teamSkills.programmingScore.toString()),
            _buildDetailRow(context, "Attempts", teamSkills.programmingAttempts.toString()),
            const SizedBox(height: 10),
            Text("$driverLabel Skills:", style: Theme.of(context).textTheme.titleMedium),
            _buildDetailRow(context, "Score", teamSkills.driverScore.toString()),
            _buildDetailRow(context, "Attempts", teamSkills.driverAttempts.toString()),

            if (!teamSkills.eligible && ineligibleReasons.isNotEmpty) ...[
              const Divider(height: 20),
              Text("Ineligibility Reasons:", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.orange.shade700)),
              for (String reason in ineligibleReasons)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: Text("• $reason", style: TextStyle(color: Colors.orange.shade300)),
                ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}