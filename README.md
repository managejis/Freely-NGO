# Freely NGO - NGO Management System (Android, Flutter)

Offline-first app for an NGO that runs children homes, old age homes and patient care. Every phone keeps its own SQLite database;
the NGO's central copy is a Google Sheet reached through an Apps Script web app. No other server. Sign-in, NGO code, invite codes,
admin approval, sync and conflict handling are the same as in Freely CMS.

## Login (same as Freely CMS)
1. The Super Admin installs the app, chooses **I am the admin**, enters the NGO name and the Google Sheet web-app URL
   (in-app setup guide; `assets/freely_ngo_apps_script.txt` is the script to paste) -> NGO created, **invite code** shown in Users.
2. The admin creates **branches** (homes / care centres), then shares the invite code.
3. A staff member chooses **I am a user**, enters mobile number, name and the invite code -> **Request access**.
4. The admin opens **Users**, **approves** the phone and gives it **roles** and (optionally) a **branch**. One-time: afterwards the app opens straight in.
5. The admin can disable a person, log every phone out, and recover the NGO on a new phone with the admin key.

## Modules in this release
Dashboard (facility filter, counts, alerts) - Children, old age residents and patients (registration, admission / discharge / re-admission /
transfer with history, care and activity records, medical records, safeguarding records) - Attendance (children, residents, staff,
volunteers; 7 statuses) - Staff and volunteers - Leave (request -> manager verifies -> administrator approves, yearly balances,
pre-filled "On leave" in staff attendance) - Donations (cash, bank and material, restricted donations, receipts, void) - Expenses
(workflow: entered -> verified -> approved -> paid) - Inventory (balance from stock transactions, stock in / issue / adjust / branch transfer,
expiry and minimum-stock alerts) - 14 reports with date and branch filters, Excel and PDF export - Users, roles and branches -
Sync with conflict detection - encrypted Backup / Restore - Audit log (including who opened medical / safeguarding information).

## Roles
Super Admin (the admin), NGO Administrator, Home Manager, Children Home / Old Age Home / Patient Care Coordinator, Doctor / Medical Staff,
Accountant, Caretaker, Volunteer, Auditor. The matrix lives in `lib/core/perms.dart` and is enforced again by `google-apps-script/Code.gs`:
a phone never receives data its roles may not read. In addition

* a person assigned to a **branch** only receives and writes that branch's records (records about a beneficiary follow the beneficiary when
  it is transferred);
* a person who is only a **coordinator** sees only their own category (children / residents / patients);
* medical records, safeguarding records, finance and staff records are separate record types with their own role lists;
* staff who may enter expenses, and anybody who requests leave, but may not read the whole list receive only their own entries;
* nobody can verify or approve their own leave request (the Super Admin excepted); approved leave can only be cancelled by the administrator.

## Business rules implemented
One unique beneficiary ID across the NGO (`CH-`, `OA-`, `PT-` + random code) - historical admission records kept in the history - transfer
between branches without a duplicate - discharged beneficiaries stay in reports - unique ids for every transaction - expense steps limited to
their role and approved / paid expenses cannot be edited, only voided - inventory balance = sum of stock transactions - donations / expenses
are never deleted - every change is audited - deleting a user never deletes the records they created.

## Develop
```
flutter pub get
flutter test                      # logic tests
node google-apps-script/test.js   # backend: approval, roles, branches, categories, expense workflow, conflicts
flutter build apk --release
```
Changing `google-apps-script/Code.gs`? Copy it to `assets/freely_ngo_apps_script.txt` too.

## Not in this release
Photos and document attachments, push notifications and reminders (follow-ups show on the dashboard), scheduled
backups, multiple languages, iOS build. Names in non-Latin scripts appear in Excel exports but not in PDF exports (the PDF font is Latin only).
Bulk Excel upload is not included here (it exists in Freely CMS and Freely MRMS).
