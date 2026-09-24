## 🎯 Scope

  

This guide deploys the build-free frontend from `app/` to Azure Static Web Apps. It does not deploy the Function App, publish documents, or change Front Door, WAF, or DNS.

  

- Production URL: `https://eslasa.lu`

- Production branch: `main`

- Workflow: `.github/workflows/deploy-static-web-app.yml`

  

Use [Azure Function Deployment](Azure-Function-Deployment.md) for API changes, [Uploading Documents](Uploading-Documents.md) for publications, and [Change and Release Management](Change-and-Release-Management.md) for infrastructure or DNS changes.

  

## ✅ Prerequisites

  

- The change record identifies scope, risk, owner, validation, and rollback.

- Public text and branding have Legal/Compliance or content-owner approval.

- The pull request targets `main` and required reviewers are available.

- The GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN` is configured and protected.

- Front Door, the Static Web App origin, and `/api/*` Function route are healthy.

- Static Web App Front Door restrictions match the current production edge values in [Infrastructure Configuration Reference](Infrastructure-Configuration-Reference.md).

- The representative test-document set is approved and available.

  

## ⚙️ Workflow behavior

  

| Event | Result |

| --- | --- |

| Pull request opened, synchronized, or reopened against `main` | Create or update a preview environment |

| Pull request closed | Remove its preview environment |

| Push or approved merge to `main` | Deploy the production frontend |

  

The workflow deploys `/app` directly with no API location, output directory, package installation, or build step. The empty API location is deliberate because the Function is separately hosted and deployed.

  

## 🔍 Local and preview review

  

Before production:

  

1. Serve `app/` with a local static server for layout and client-interaction review.

2. Check navigation, anchors, search, empty/error states, links, and browser console.

3. Check keyboard operation, visible focus, reduced motion, 200% zoom, and responsive viewports.

4. Open the pull-request preview and repeat relevant checks.

5. Confirm the preview's API limitations are understood; production `/api/*` behavior is provided by Front Door, not the Static Web Apps workflow.

6. Record evidence and approvals on the change or pull request.

  

Use [Testing and Acceptance Checklist](Testing-and-Acceptance-Checklist.md) for a major release or acceptance event.

  

## 📦 Production procedure

  

1. Confirm the branch is current with `main` and the pull request contains only approved changes.

2. Confirm checks and required reviews have passed.

3. Confirm the rollback commit and authorised operator are known.

4. Merge the pull request to `main` through the protected branch process.

5. Monitor the **Deploy Azure Static Web App** workflow to completion.

6. Record the commit and workflow run as release evidence.

7. Perform production verification through Front Door.

8. Monitor availability, Front Door origin health, WAF, and client errors during the agreed observation period.

  

Never expose the deployment token in logs, screenshots, pull requests, or documentation.

  

## ✅ Production verification

  

Verify externally through `https://eslasa.lu`:

  

- HTTPS page load and expected page title/content.

- Header, navigation, anchors, footer, email, and external links.

- Desktop, mobile, keyboard, focus, and representative accessibility behavior.

- Search and document category rendering.

- `/api/documents` returns the expected approved set.

- At least one representative document opens from each populated category.

- Browser console and network panel show no unexpected errors.

- Front Door website and API origins remain healthy.

- WAF does not block expected requests.

- The production commit corresponds to the approved release.

  

## ↩️ Rollback

  

Rollback when the change causes availability loss, incorrect public content, broken navigation or documents, material accessibility regression, unexpected client errors, or failed acceptance.

  

1. Stop additional changes and notify the release owner.

2. Revert the responsible commit through the approved Git/pull-request process.

3. Merge the rollback to `main` so the existing workflow redeploys the previous state.

4. Repeat production verification.

5. Monitor stability and preserve failure and rollback evidence.

6. Keep the failed change or incident open until ownership and corrective action are assigned.

  

An incorrect document is not a frontend rollback. Follow the authorised withdrawal process in [Uploading Documents](Uploading-Documents.md).

  

## 🧯 Failure handling

  

| Symptom | Action |

| --- | --- |

| Workflow cannot authenticate | Verify the secret exists, is current, and belongs to the intended Static Web App; rotate through the approved process if needed |

| Workflow attempts an application build | Confirm `skip_app_build: true`, `/app`, and empty API/output locations |

| Preview fails but workflow succeeds | Review preview environment status and unsupported production API routing assumptions |

| Production has old content | Confirm the successful run targeted `main`, verify commit, bypass local cache, and check Static Web App deployment history |

| Direct origin works but public site fails | Escalate to Front Door/WAF/DNS diagnosis in the incident guide |

| Page works but documents fail | Diagnose the public API route and Function rather than redeploying the frontend |

  

See [Incident and Troubleshooting Guide](Incident-and-Troubleshooting-Guide.md) for cross-service diagnosis.

  

## 📋 Release record

  

Record the change ID, pull request, approved commit, workflow run, approvers, test evidence, production verification, observation outcome, and rollback result if used. The release is complete only when evidence is stored and monitoring is stable.