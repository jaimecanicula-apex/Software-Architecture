# Golden templates: roadmap

All three infrastructure designs in this repository are proofs of concept, written to become **APEX golden templates**: approved, versioned starting points that any team can use to publish a static website without redesigning the infrastructure.

| Template | Folder | Use when |
| --- | --- | --- |
| Publicly accessible static website | `publicly-accessible-static-website/` | The audience is **external**: clients or users outside APEX |
| Public sign-in static website | `public-signin-static-website/` | The audience is **approved external people** who must sign in with Entra ID (B2B guests of the APEX tenant) before seeing any page |
| Privately accessible static website | `privately-accessible-static-website/` | The audience is **internal**: anyone signing in with APEX Entra ID (colleagues, APEX companies, contractors). No internet exposure. |

## Already in place

- **Parameterized:** every environment-specific value comes from `terraform.tfvars`: subscription, tenant, region, SKUs, network ranges, groups, thresholds and tags. Nothing is hard-coded to one client.
- **Structured:** reusable modules sit behind one root stack per design, with separate settings and state per environment (dev, qa, uat, prod).
- **Governed:** mandatory governance tags, naming convention, delete locks, budgets and least-privilege viewer and operator roles.
- **Monitored:** all three designs include full monitoring by default. One switch, `enable_monitoring`, turns all of it off per environment (for example in dev to save cost); it cannot be off in prod.
- **Pinned:** provider versions are pinned and lock files are committed.

## Still needed before publishing as golden templates

1. **Versioned module source.** Move `modules/` into a module registry (a private Terraform registry, or a Git repo with semver tags). Stacks then reference `source = "<registry>/static-web-app/azurerm" version = "~> 1.0"` instead of relative paths.
2. **One shared module library.** The three designs currently carry their own copies of `naming`, `static-web-app`, `monitoring`, `front-door`, `front-door-waf` and `entra-app-auth`. Merge them into one versioned library, where the private variant's extra inputs (`public_network_access_enabled`, private ingestion, custom availability tests) are ordinary options.
3. **Landing-zone integration.** In the private design, replace the self-created Private DNS zones with the platform team's central zones, and accept an existing spoke subnet as an input.
4. **Policy alignment.** Check all three designs against the APEX Azure Policy assignments (allowed regions and SKUs, private endpoints, diagnostic settings, tags) and remove anything the policies already enforce.
5. **Tests.** Add `terraform test` suites and a CI pipeline: `fmt`, `validate`, `tflint`, `checkov` or `trivy`, and a plan per environment on every pull request.
6. **Infrastructure pipeline.** Add plan on pull request and apply per environment with approval gates, using OIDC (workload identity federation) instead of secrets.
7. **Documentation contract.** For each template, document its inputs, outputs, supported regions, cost baseline, RACI and support model, generated with `terraform-docs`.
8. **Release process.** Use semver releases, a changelog, and a deprecation policy, so consuming teams can upgrade on their own schedule.
9. **Ownership.** Name the owning team, the review board that approves changes, and the review cadence.
