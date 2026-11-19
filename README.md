# Summative-scripting — Attendance Tracker Deployment Agent

`deploy_agent.sh` is an interactive Bash tool that deploys the Python
Student Attendance Tracker, runs it, and archives its logs.

## Requirements

- Bash 4+
- Python 3
- `zip`
- Standard Unix tools (`sed`, `awk`, `cp`, `chmod`, `date`)

## Usage

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

Menu:

| Option | Action |
|--------|--------|
| 1 | Deploy application |
| 2 | Run application |
| 3 | Archive logs |
| 4 | Exit |

### 1. Deploy

1. Checks that `python3`, `zip` and the `templates/` folder are available.
2. Asks for a project name (letters, digits, `_`, `-`) and creates
   `attendance_tracker_<name>/`. If it already exists you can overwrite it or cancel.
3. Builds this layout:

   ```text
   attendance_tracker_<name>/
   ├── attendance_checker.py      (executable)
   ├── Helpers/
   │   ├── config.json            (mode 600)
   │   └── assets.csv
   ├── reports/
   └── archives/
   ```

4. Roster choice: keep the template counts, or reset every student to 0/0.
5. Optionally changes the warning/failure thresholds (defaults 75 / 50).
   Values must be whole numbers 0–100 and failure cannot exceed warning.
   The new values are written into `config.json` with `sed`.
6. Starts the attendance checker once deployment succeeds.

### 2. Run

Enter the name of a deployed project; the agent runs
`attendance_checker.py` from inside that project directory.

### 3. Archive logs

Copies `reports/attendance.log` and `reports/absent.log` into
timestamped files:

```text
archives/attendance/attendance_YYYYMMDD_HHMMSS.log
archives/absent/absent_YYYYMMDD_HHMMSS.log
```

A missing log is reported and skipped.

## Interrupt handling

While a deployment is in progress, **Ctrl+C** (SIGINT) or **Ctrl+Z**
(SIGTSTP) triggers a `trap` handler that:

1. zips the partially built project into `attendance_tracker_<name>_archive.zip`;
2. deletes the incomplete directory if the zip succeeded (keeps it otherwise);
3. exits with status 130.

The trap is removed as soon as deployment finishes, so it never interferes
with an attendance-marking session.

## Testing

```bash
bash -n deploy_agent.sh   # syntax check
```

Manual checks performed:

- deploy with each roster option, default and custom thresholds
- invalid project names, invalid/out-of-range thresholds, failure > warning
- overwrite vs. cancel for an existing project
- run an existing project and a non-existent one
- archive with logs present and missing
- Ctrl+C and Ctrl+Z during deployment produce the zip and remove the directory

## Repository structure

```text
Summative-scripting/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py
    ├── config.json
    └── assets.csv
```
