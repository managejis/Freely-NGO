import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/reports.dart';
import '../core/store.dart';
import '../core/users.dart';
import '../ui.dart';
import '../widgets.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'auth_screens.dart';
import 'backup_screen.dart';
import 'beneficiaries_screen.dart';
import 'branches_screen.dart';
import 'donations_screen.dart';
import 'expenses_screen.dart';
import 'info_screens.dart';
import 'inventory_screen.dart';
import 'leave_screen.dart';
import 'people_screen.dart';
import 'reports_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'users_screen.dart';

void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _branch = '';   // dashboard filter: '' = every facility the person may see

  void _quickAdd() {
    final items = <(IconData, String, Color, VoidCallback)>[
      if (Perms.editBeneficiaries) for (final c in Perms.allowedCategories) (Icons.person_add_alt_1, 'Register ${categoryLabels[c]!.toLowerCase()}', c == catChild ? accentOrange : (c == catElder ? accentViolet : accentPink), () => startRegistration(context, category: c)),
      if (Perms.takeAttendance) (Icons.fact_check_outlined, 'Take attendance', accentGreen, () => go(context, const TakeAttendanceScreen())),
      (Icons.event_busy_outlined, 'Request leave', accentSky, () => go(context, const LeaveScreen())),
      if (Perms.editDonations) (Icons.volunteer_activism, 'Add donation', accentGreen, () => go(context, const DonationsScreen())),
      if (Perms.enterExpenses) (Icons.receipt_long_outlined, 'Enter expense', accentOrange, () => go(context, const ExpensesScreen())),
      if (Perms.editPeople) (Icons.badge_outlined, 'Add staff / volunteer', accentSky, () => go(context, const PeopleScreen())),
      if (Perms.editAnnouncements) (Icons.campaign_outlined, 'Post announcement', accentPink, () => go(context, const AnnouncementsScreen())),
    ];
    if (items.isEmpty) {
      toast(context, 'Nothing to add with your role. Ask the admin if you need more access.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            for (final i in items)
              ListTile(
                leading: CircleAvatar(backgroundColor: i.$3.withValues(alpha: 0.16), child: Icon(i.$1, color: i.$3)),
                title: Text(i.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(c); i.$4(); },
              ),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      drawer: const _AppDrawer(),
      floatingActionButtonLocation: brandFabLocation,
      floatingActionButton: BrandFab(icon: Icons.add, tooltip: 'Quick add', onPressed: _quickAdd),
      bottomNavigationBar: BrandBottomBar(items: [
        NavItem(Icons.home_rounded, 'Home', () {}, selected: true),
        NavItem(Icons.groups_rounded, 'Beneficiaries', () => go(context, const BeneficiariesScreen())),
        NavItem(Icons.notifications_none_rounded, 'Announcements', () => go(context, const AnnouncementsScreen())),
        NavItem(Icons.person_outline_rounded, 'Profile', () => go(context, const ProfileScreen())),
      ]),
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Builder(
            builder: (c) => Row(children: [
              RoundIconButton(icon: Icons.menu_rounded, tooltip: 'Menu', onTap: () => Scaffold.of(c).openDrawer()),
              const Spacer(),
              const BrandTitle(),
              const Spacer(),
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                child: const ClipOval(child: OrgAvatar(size: 40)),
              ),
            ]),
          ),
        ),
      ),
      body: Live<_Home>(load: _load, builder: (c, h) => _Dashboard(h, branch: _branch, onBranch: (v) => setState(() => _branch = v))),
    );
  }

  Future<_Home> _load() async {
    await Store.loadBranchNames();
    final branches = await Store.branches();
    final ann = await Store.announcements();
    return _Home(branches, await dashStats(_branch), ann);
  }
}

class _Home {
  final List<Rec> branches;
  final DashStats stats;
  final List<Rec> announcements;
  _Home(this.branches, this.stats, this.announcements);
}

class _Tile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool badge;
  _Tile(this.icon, this.label, this.color, this.onTap, {this.badge = false});
}

class _Dashboard extends StatelessWidget {
  final _Home h;
  final String branch;
  final ValueChanged<String> onBranch;
  const _Dashboard(this.h, {required this.branch, required this.onBranch});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final s = h.stats;
    final first = app.userName.split(' ').first;
    final urgent = h.announcements.where((a) => a.data['urgent'] == true).toList();
    final cats = Perms.allowedCategories;
    final alerts = s.followUps + s.lowStock + s.expirySoon + s.pendingExpenses + s.pendingLeave;

    final pills = <(IconData, String, VoidCallback)>[
      if (Perms.beneficiaries) for (final c in cats) (_catIcon(c), categoryPlural[c]!, () => go(context, BeneficiariesScreen(category: c))),
      if (Perms.attendance) (Icons.fact_check_outlined, 'Attendance', () => go(context, const AttendanceScreen())),
      if (Perms.donations) (Icons.volunteer_activism_outlined, 'Donations', () => go(context, const DonationsScreen())),
      if (Perms.expenses || Perms.enterExpenses) (Icons.receipt_long_outlined, 'Expenses', () => go(context, const ExpensesScreen())),
      if (Perms.inventory) (Icons.inventory_2_outlined, 'Inventory', () => go(context, const InventoryScreen())),
      if (Perms.reports) (Icons.insights_outlined, 'Reports', () => go(context, const ReportsScreen())),
    ];
    final tiles = <_Tile>[
      if (Perms.beneficiaries) _Tile(Icons.groups_rounded, 'Beneficiaries', accentViolet, () => go(context, const BeneficiariesScreen())),
      if (Perms.attendance) _Tile(Icons.fact_check_rounded, 'Attendance', accentGreen, () => go(context, const AttendanceScreen())),
      if (Perms.people) _Tile(Icons.badge_rounded, 'Staff', accentSky, () => go(context, const PeopleScreen())),
      _Tile(Icons.event_busy_rounded, 'Leave', accentOrange, () => go(context, const LeaveScreen())),
      if (Perms.donations) _Tile(Icons.volunteer_activism_rounded, 'Donations', accentGreen, () => go(context, const DonationsScreen())),
      if (Perms.expenses || Perms.enterExpenses) _Tile(Icons.receipt_long_rounded, 'Expenses', accentOrange, () => go(context, const ExpensesScreen())),
      if (Perms.inventory) _Tile(Icons.inventory_2_rounded, 'Inventory', accentPink, () => go(context, const InventoryScreen())),
      if (Perms.reports) _Tile(Icons.insights_rounded, 'Reports', brandBlue, () => go(context, const ReportsScreen())),
      _Tile(Icons.apartment_rounded, 'Branches', accentSky, () => go(context, const BranchesScreen())),
      _Tile(Icons.campaign_rounded, 'Notices', accentPink, () => go(context, const AnnouncementsScreen())),
      if (app.isAdmin) _Tile(Icons.manage_accounts_rounded, 'Users', accentViolet, () => go(context, const UsersScreen())),
      if (app.isAdmin) _Tile(Icons.how_to_reg_rounded, 'Approvals', accentOrange, () => go(context, const UsersScreen()), badge: true),
      _Tile(Icons.backup_rounded, 'Backup', accentGreen, () => go(context, const BackupScreen())),
    ];

    final stats = <_Stat>[
      if (Perms.beneficiaries) ...[
        _Stat('Beneficiaries', '${s.total}', Icons.groups_rounded, accentViolet),
        if (cats.contains(catChild)) _Stat('Children in homes', '${s.children}', Icons.child_care, accentOrange),
        if (cats.contains(catElder)) _Stat('Old age residents', '${s.elders}', Icons.elderly, accentViolet),
        if (cats.contains(catPatient)) _Stat('Active patients', '${s.patients}', Icons.medical_services_outlined, accentPink),
        _Stat('New admissions (month)', '${s.admissionsMonth}', Icons.login, accentGreen),
        _Stat('Discharges (month)', '${s.dischargesMonth}', Icons.logout, accentSky),
      ],
      if (Perms.people) ...[_Stat('Staff', '${s.staff}', Icons.badge_outlined, accentSky), _Stat('Volunteers', '${s.volunteers}', Icons.volunteer_activism_outlined, accentGreen)],
      if (Perms.leaveAll) _Stat('Staff on leave today', '${s.onLeaveToday}', Icons.event_busy_outlined, accentSky),
      if (Perms.attendance) _Stat("Today's attendance", s.sheetsToday == 0 ? 'not taken' : '${s.presentToday} present', Icons.fact_check_outlined, accentGreen),
      if (Perms.care || Perms.medical) _Stat('Follow-ups due', '${s.followUps}', Icons.event_repeat, s.followUps > 0 ? accentOrange : accentGreen),
      if (Perms.donations) _Stat('Donations (month)', money(s.donationsMonth), Icons.south_west_rounded, accentGreen),
      if (Perms.expenses) _Stat('Expenses paid (month)', money(s.expensesMonth), Icons.north_east_rounded, accentOrange),
      if (Perms.inventory) _Stat('Stock alerts', '${s.lowStock + s.expirySoon}', Icons.inventory_2_outlined, s.lowStock + s.expirySoon > 0 ? accentOrange : accentGreen),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 110), children: [
      Text('Hi, $first', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 14)),
      const SizedBox(height: 2),
      Text(greeting(), style: serif(36)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () => go(context, const SearchScreen()),
        child: AbsorbPointer(child: TextField(decoration: searchDecoration('Search beneficiaries, staff, notices'))),
      ),
      if (app.branch.isEmpty && h.branches.length > 1) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All facilities'), selected: branch.isEmpty, onSelected: (_) => onBranch(''))),
            for (final b in h.branches) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(b.s('name')), selected: branch == b.id, onSelected: (_) => onBranch(b.id))),
          ]),
        ),
      ] else if (app.branch.isNotEmpty) ...[
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: Chip(avatar: const Icon(Icons.apartment, size: 18), label: Text(Store.branchName(app.branch)))),
      ],
      if (pills.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, children: [for (var i = 0; i < pills.length; i++) PillChip(icon: pills[i].$1, label: pills[i].$2, onTap: pills[i].$3, filled: i == 0)]),
        ),
      ],
      if (urgent.isNotEmpty) ...[
        const SizedBox(height: 16),
        Material(
          color: const Color(0xFFFFE1E4),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => go(context, const AnnouncementsScreen()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.campaign, color: Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Urgent announcement', style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                  Text(urgent.first.s('title'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                ])),
                const Icon(Icons.chevron_right, color: Colors.black54),
              ]),
            ),
          ),
        ),
      ],
      if (alerts > 0) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: gradientOf(gOrange), borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.notifications_active_outlined, color: accentOrange)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                [
                  if (s.followUps > 0) '${s.followUps} follow-up${s.followUps == 1 ? '' : 's'} due',
                  if (s.pendingExpenses > 0) '${s.pendingExpenses} expense${s.pendingExpenses == 1 ? '' : 's'} not yet paid',
                  if (s.pendingLeave > 0) '${s.pendingLeave} leave request${s.pendingLeave == 1 ? '' : 's'} pending',
                  if (s.lowStock > 0) '${s.lowStock} item${s.lowStock == 1 ? '' : 's'} low on stock',
                  if (s.expirySoon > 0) '${s.expirySoon} item${s.expirySoon == 1 ? '' : 's'} expiring / expired',
                ].join(' · '),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ],
      if (stats.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text('Overview', style: serif(24)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: stats),
      ],
      const SizedBox(height: 22),
      Text('Tools', style: serif(24)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 0.95,
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        children: [for (final t in tiles) _TileView(t)],
      ),
      const SizedBox(height: 14),
      Align(alignment: Alignment.center, child: SyncChip(onTap: () => go(context, const SyncScreen()))),
    ]);
  }

  IconData _catIcon(String c) => c == catChild ? Icons.child_care : (c == catElder ? Icons.elderly : Icons.medical_services_outlined);
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width - 40 - 12) / 2;
    return Container(
      width: w,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(22), boxShadow: softShadow(context)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        ])),
      ]),
    );
  }
}

class _TileView extends StatelessWidget {
  final _Tile t;
  const _TileView(this.t);
  @override
  Widget build(BuildContext context) {
    Widget icon = Container(
      width: 52, height: 52,
      decoration: BoxDecoration(color: t.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
      child: Icon(t.icon, color: t.color, size: 28),
    );
    if (t.badge) {
      final i = icon;
      icon = ListenableBuilder(listenable: Users.pending, builder: (_, __) => Badge(isLabelVisible: Users.pending.value > 0, label: Text('${Users.pending.value}'), child: i));
    }
    return Container(
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: t.onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          icon,
          const SizedBox(height: 8),
          Text(t.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    void open(Widget w) {
      Navigator.pop(context);
      go(context, w);
    }

    Widget item(IconData i, String t, VoidCallback f) => ListTile(leading: Icon(i), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)), onTap: f);

    return Drawer(
      backgroundColor: panelColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(32))),
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 22, 20, 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [skyTop, brandBlue]),
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(32)),
          ),
          child: Row(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)), child: const ClipOval(child: OrgAvatar(size: 54))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.orgName, style: serif(21, color: Colors.white)),
                Text(app.userName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(app.isAdmin ? 'Super Admin' : Perms.rolesText(app.roles), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        item(Icons.person_outline, 'Profile', () => open(const ProfileScreen())),
        item(Icons.settings_outlined, 'Settings', () => open(const SettingsScreen())),
        item(Icons.sync, 'Synchronization status', () => open(const SyncScreen())),
        item(Icons.backup_outlined, 'Backup / Restore', () => open(const BackupScreen())),
        if (app.isAdmin) item(Icons.history, 'Audit log', () => open(const AuditScreen())),
        item(Icons.privacy_tip_outlined, 'Privacy & Security', () => open(const PrivacyScreen())),
        item(Icons.help_outline, 'Help & Support', () => open(const HelpScreen())),
        item(Icons.info_outline, 'About App', () => open(const AboutScreen())),
        const Divider(),
        item(Icons.logout, 'Logout', () {
          Navigator.pop(context);
          logoutFlow(context);
        }),
      ]),
    );
  }
}
