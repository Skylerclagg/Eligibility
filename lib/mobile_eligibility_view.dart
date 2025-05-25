// lib/mobile_eligibility_view.dart
import 'package:flutter/material.dart';
import 'models.dart';
import 'team_eligibility_detail_page.dart';

class MobileEligibilityView extends StatelessWidget {
  final List<TeamSkills> eligibleRecords;
  final List<TeamSkills> ineligibleRecords;
  final RobotProgram? selectedProgram;
  final ProgramRules? programRules;

  const MobileEligibilityView({
    super.key,
    required this.eligibleRecords,
    required this.ineligibleRecords,
    required this.selectedProgram,
    required this.programRules, required List<TeamSkills> records,
  });

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildMobileTeamRow(BuildContext context, TeamSkills record) {
    final team = record.team;
    
    // Construct location string using city, state (region), and country
    List<String> locationParts = [];
    if (team.city.isNotEmpty) locationParts.add(team.city);
    if (team.state.isNotEmpty) locationParts.add(team.state); // team.state is our region
    if (team.country.isNotEmpty) locationParts.add(team.country);
    final String locationString = locationParts.join(", ");

    return InkWell(
      onTap: () {
        if (selectedProgram != null && programRules != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeamEligibilityDetailPage(
                teamSkills: record,
                selectedProgram: selectedProgram!,
                programRules: programRules!,
              ),
            ),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            children: [
              Text(
                team.number,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: record.eligible ? Colors.green.shade700 : Colors.grey.shade700,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis,),
                    if (locationString.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(locationString, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600), overflow: TextOverflow.ellipsis,),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                record.eligible ? Icons.check_circle_outline : Icons.highlight_off,
                color: record.eligible ? Colors.green.shade600 : Colors.red.shade700,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (eligibleRecords.isEmpty && ineligibleRecords.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("No teams to display with current filters."),
      ));
    }
    
    List<Widget> listItems = [];

    if (eligibleRecords.isNotEmpty) {
      listItems.add(_buildSectionHeader(context, "Eligible Teams (${eligibleRecords.length})"));
      for (var record in eligibleRecords) {
        listItems.add(_buildMobileTeamRow(context, record));
      }
    }

    if (ineligibleRecords.isNotEmpty) {
      if (listItems.isNotEmpty) {
        listItems.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Divider(height: 1, thickness: 1),
        ));
      }
      listItems.add(_buildSectionHeader(context, "Ineligible Teams (${ineligibleRecords.length})"));
      for (var record in ineligibleRecords) {
        listItems.add(_buildMobileTeamRow(context, record));
      }
    }
    
    return ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 80), 
        children: listItems,
    );
  }
}