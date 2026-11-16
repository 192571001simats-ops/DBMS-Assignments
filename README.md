# DBMS Assignments

**Name:** Athisaya U  
**Registration number:** 192571001  
**Course:** CSA05 Database Management Systems  
**Institution:** SIMATS Engineering

Repository: https://github.com/192571001simats-ops/DBMS-Assignments

| Assignment | Submission PDF | Editable document | Code |
|---|---|---|---|
| 1 CO1 Museum design | [PDF](CSA05_CO1_Sentence_Formatting_Corrected.pdf) | [Word](CSA05_CO1_Sentence_Formatting_Corrected.docx) | [SQL](CO1_Taskwise_SQL.sql) |
| 2 CO2 Courier handover | [PDF](CSA05_CO2_Completed_Faculty_Format.pdf) | [Word](CSA05_CO2_Completed_Faculty_Format.docx) | [SQL](CO2_Taskwise_SQL.sql) |
| 3 CO3 Retail normalization | [PDF](CSA05_CO3_Completed_Faculty_Format.pdf) | [Word](CSA05_CO3_Completed_Faculty_Format.docx) | [SQL](CO3_Taskwise_SQL.sql) |
| 4 CO4 Bank storage and indexing | [PDF](CSA05_CO4_Completed_Faculty_Format.pdf) | [Word](CSA05_CO4_Completed_Faculty_Format.docx) | [Python](CSA05_CO4_Experiment.py) · [Results package](CSA05_CO4_Code_and_Results.zip) |

Each document includes the student details and clickable repository link. Assignments 1–3 contain SQL under their respective task answers. Assignment 4 uses the Python block-level simulation requested by its question paper.

## Run the added SQL for Assignments 1–3

Use SQLite 3 in a fresh connection for each assignment. Each SQL file places the complete setup first, followed by Task 1 to Task 12. The documents print setup within Task 8, so execute that setup before running their task queries. All 36 added task blocks were executed against the included small fixtures; foreign-key checks and selected expected results passed. These examples are separate from the original large benchmark experiments described in the assignments.

## Run Assignment 4

Use Python 3 with no external dependencies:

```sh
python3 CSA05_CO4_Experiment.py
```

The script generates `results.csv`, `structure.csv`, `upi.csv` and `validation.json` beside itself. It tests heap, static hash and clustered B+ storage at 1,000, 10,000, 100,000 and 1,000,000 records and compares a full 200,000-insert gateway workload. Allow several minutes. The results ZIP includes the measured tables, validation status, tree traces and performance plot used in the report.

Counts model logical 4-KiB page reads/writes. Python execution time is not hardware disk latency; concurrency, durability and crash recovery are outside this simulation. The report distinguishes measured variants from analytical designs.
