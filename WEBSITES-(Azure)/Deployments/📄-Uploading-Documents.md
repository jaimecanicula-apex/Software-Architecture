## 🎯 Purpose

  

This is the authoritative procedure for publishing approved PDFs to the Esla S.A. website with the repository PowerShell script. A normal publication does not require a website or Function deployment.

  

The current target and supported metadata are recorded in [Infrastructure Configuration Reference](Infrastructure-Configuration-Reference.md). Confirm the script output identifies the intended production environment before publishing.

  

## 🔐 Control requirements

  

- Legal/Compliance and the designated content owner have approved the final file, category, publication date, filename, and announcement wording.

- The publisher is authorised for the production Blob container through Microsoft Entra ID and an approved data-plane role.

- Approval and technical publication are separated when organisational policy requires it.

- The source folder contains only the PDFs in the approved batch.

- Every public filename is clear, unique, and contains no draft or confidential marker.

- A reviewer and withdrawal decision-maker are available for time-critical publication.

  

Never request, share, or store keys, SAS tokens, passwords, or other credentials in the repository, command history, evidence, or documentation.

  

## 🗂️ Supported categories

  

The final source-folder name determines the website category.

  

| Website section | Required folder name |

| --- | --- |

| Information Memorandum and Transaction Terms | `information-memorandum` |

| Announcements | `announcements` |

| Financial Reports | `financial-reports` |

| Corporate Documents | `corporate-documents` |

  

The script lowercases the folder name and converts spaces or underscores to hyphens, but exact names above are required practice.

  

## 🏷️ Metadata behavior

  

The script uploads only `*.pdf` and applies:

  

```text

approved=true

category=<category derived from folder name>

publicationdate=<publisher workstation local date in YYYY-MM-DD>

description=<approved announcement description, announcements only>

```

  

The API supports optional `displayname`, but the current publishing script does not set it. The API may expose approved text files placed by another authorised process; this script uploads PDFs only.

  

## 🚀 Standard publication

  

1. Create a local folder with the exact category name.

2. Copy only the final approved PDFs for this publication into it.

3. Compare each PDF and filename with the approval record.

4. Confirm the workstation date; it becomes `publicationdate`.

5. From the repository root in PowerShell, run:

  

```powershell

.\.github\skills\upload-blob-documents\scripts\upload-documents.ps1 `

  -SourcePath "C:\Publications\financial-reports"

```

  

6. Complete the interactive Azure CLI sign-in with the authorised publisher identity.

7. Before accepting the result, review the displayed account, container, source, category, date, and PDF count.

8. Confirm the upload completes without overwrite errors.

9. Perform all post-publication checks below.

10. Store approval and publication evidence in the controlled record.

  

## 📣 Announcements

  

Announcements require an approved public description:

  

```powershell

.\.github\skills\upload-blob-documents\scripts\upload-documents.ps1 `

  -SourcePath "C:\Publications\announcements" `

  -Description "Approved public announcement description"

```

  

If omitted, the script prompts for the description and rejects an empty response. Do not include internal comments, draft labels, personal data, or confidential information.

  

## 🛡️ Safety behavior

  

The script:

  

- Rejects a missing directory, empty PDF set, or unsupported category.

- Requires an announcement description.

- Authenticates with Azure CLI and `--auth-mode login`.

- Uses `--overwrite false`; an existing Blob is not replaced.

- Uploads matching PDFs only and does not upload code or settings files.

  

If any displayed target or metadata is wrong, stop. Do not compensate with an unapproved Azure Portal change.

  

## ✅ Post-publication verification

  

For every file:

  

1. Refresh `https://eslasa.lu` and locate the expected category.

2. Confirm the public title/filename, category, date, and announcement description.

3. Open the document through the public website.

4. Compare the rendered/downloaded PDF with the approved original.

5. Confirm no unrelated or unapproved document became visible.

6. Confirm `/api/documents` contains the expected public metadata when technical evidence is required.

7. Record publisher, reviewer, time, files, approval reference, target, and verification evidence.

  

## ↩️ Withdrawal, correction, or replacement

  

The upload script intentionally does not automate these high-impact actions.

  

1. Treat an incorrect, unapproved, outdated, or confidential publication as a content incident.

2. Notify Legal/Compliance, the content owner, and incident owner immediately.

3. Preserve the original approval, Blob metadata, public evidence, and timeline.

4. Obtain explicit withdrawal or correction approval.

5. Have an authorised Storage operator perform the narrowly approved metadata or Blob action.

6. Verify the document is no longer listed or downloadable as required.

7. Publish a corrected file with a unique approved filename when authorised.

8. Repeat all verification and retain the complete audit trail.

  

Do not silently delete, overwrite, rename, or alter metadata on production publications.

  

## 🧯 Troubleshooting

  

| Problem | Action |

| --- | --- |

| Azure CLI unavailable | Install the approved Azure CLI version and reopen PowerShell |

| Sign-in or tenant failure | Confirm corporate account, tenant, and conditional-access requirements |

| Authorization failure | Ask the platform owner to verify the publisher's scoped Blob data-plane role |

| Unsupported category | Rename the final folder to an exact supported category |

| No PDFs found | Check the selected directory and `.pdf` extensions |

| Blob already exists | Stop; use a unique approved filename or authorised replacement process |

| Wrong target, category, or date shown | Stop before publication and correct the controlled input or configuration |

| Upload succeeds but document is absent | Check public API metadata, target reconciliation, and cache behavior; do not re-upload blindly |

| Website or API unavailable | Follow [Incident and Troubleshooting Guide](Incident-and-Troubleshooting-Guide.md) |

  

## 📋 Publication record

  

Record the approval reference, publisher, reviewer, publication timestamp, filenames and hashes where policy requires, category, description, target environment, script result, public URLs, verification evidence, and any incident/change reference.