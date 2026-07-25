# Using AI Safely in the Standard Delivery Pipeline

> **Status:** Proposed extension to the
> [Ideal Standard Software Delivery Flow](IDEAL_FLOW.md).
>
> **Purpose:** Define where autonomous AI repair is useful, what authority it may
> receive, and which controls must remain outside its reach.

## Core principle

Give AI **high autonomy inside a low-authority, disposable environment**.

AI may propose and prove a change. It may not authorize its own promotion.

A disposable Git branch is useful for attribution and recovery, but it is not a
security sandbox. The actual security boundaries are:

- workflow and branch permissions;
- filesystem and network isolation;
- runner lifetime and trust level;
- credential scope and lifetime;
- protected files and control definitions;
- independently executed tests and policies;
- environment separation and promotion authority.

## Intended use

This pattern is designed for an AI agent that:

1. receives structured evidence from a failed test-branch pipeline;
2. analyzes the failure in a fresh isolated environment;
3. modifies an explicitly allowed part of the repository;
4. runs bounded local validation;
5. commits only to an AI-writable test branch;
6. submits the result to a clean, independently controlled CI run;
7. repeats within fixed limits or escalates;
8. opens a pull request when all required evidence passes.

It is not a design for autonomous production authorization, unrestricted repository
administration, or self-approved security exceptions.

## Reference branch model

```text
protected feature branch
        |
        | create or reset an AI test branch from an approved commit
        v
AI-writable test branch
        |
        | AI edits, validates locally, and commits within policy
        v
independent CI from a trusted workflow definition
        |
        +-- fail --> sanitized evidence --> bounded AI retry
        |                                  |
        |                                  +-- limit reached --> escalation
        |
        +-- pass --> remediation pull request into feature branch
                                               |
                                               v
                                  independent review + clean CI
                                               |
                                               v
                                    eligible for protected staging
```

The feature branch preserves the approved baseline. The test branch provides a
disposable workspace and a complete record of AI attempts. Required checks must rerun
after the remediation pull request is created; results produced inside the AI session
are supporting evidence, not the final control.

## Branch and authority contract

| Surface | AI authority | Required boundary |
|---|---|---|
| AI test branch | Edit, commit, and push | Cannot bypass branch rules or write elsewhere |
| Feature branch | Open a pull request | No direct push, merge, or self-approval |
| Default branch | None | Protected rules and required checks |
| Application source | Edit within an allowlist | Diff, size, and policy limits |
| New tests | May add | Must not replace independent acceptance evidence |
| Existing required tests | Proposal only | Deletion or weakening requires independent review |
| Dependencies | Conditional | Lockfile review, license policy, vulnerability scan |
| CI workflows and actions | None | Loaded from a protected source |
| Security policy and scanner configuration | None | Changes follow a separate controlled path |
| Ownership and branch rules | None | Administrative boundary |
| Test environment | Conditional deployment | Disposable resources and expiring credentials |
| Staging | No direct promotion | Protected authorization after clean CI |
| Production | No credentials or authorization | Independent protected deployment path |

## Autonomous repair state machine

```text
FAILED
  -> COLLECT_EVIDENCE
  -> START_ISOLATED_ATTEMPT
  -> ANALYZE
  -> PATCH
  -> LOCAL_VALIDATE
       -> local failure and attempts remain: ANALYZE
       -> policy violation: ESCALATE
       -> local pass: INDEPENDENT_CI
            -> CI failure and attempts remain: COLLECT_EVIDENCE
            -> CI pass: OPEN_REMEDIATION_PR
            -> limit reached: ESCALATE
```

Each transition must be explicit and logged. A timeout, missing result, invalid
structured output, unavailable sandbox, or failed evidence upload is a failure, never
an implicit pass.

## Required containment controls

### 1. Trusted orchestration

The workflow that grants AI authority must come from a protected reference or a
separately controlled automation repository. Do not trust a privileged workflow
definition loaded from the AI-writable branch.

The untrusted checkout is data supplied to the trusted workflow. It must not be able to:

- replace the workflow that evaluates it;
- alter the list of required checks;
- change protected path rules;
- request broader permissions through repository-controlled configuration;
- convert a read-only job into a deployment job.

Third-party actions and reusable workflows should be pinned to reviewed immutable
revisions.

### 2. Ephemeral execution

Start each AI attempt on a clean, short-lived runner or sandbox and destroy it
afterward. Do not reuse its workspace for a trusted build or deployment.

The execution environment should:

- run without privileged mode or a mounted host container socket;
- have no persistent SSH keys, cloud profiles, kubeconfig, or production tooling state;
- use read-only base images and a writable disposable workspace;
- enforce CPU, memory, storage, process, and time limits;
- discard caches unless their integrity and trust boundaries are defined;
- fail closed when isolation cannot be established.

### 3. Filesystem isolation

Use an allowlist for writable application paths and an enforceable deny list for
control-plane files.

Typical protected paths include:

```text
.github/**
CODEOWNERS
**/pipeline-policy.*
**/security-policy.*
**/branch-rules.*
**/deployment-credentials.*
**/production/**
```

The exact list depends on the repository. Enforcement must occur outside the model,
such as in the trusted workflow or repository policy. Instructions in a prompt are not
an access-control mechanism.

### 4. Network isolation

Default-deny outbound access, then allow only required model endpoints, approved
dependency sources, and explicitly selected test services.

Network controls should prevent:

- arbitrary data exfiltration;
- access to metadata services;
- access to internal control planes;
- calls to production APIs;
- downloads from unapproved script or package sources;
- lateral movement into persistent infrastructure.

If broader access is genuinely required, place it behind an authenticated proxy that
logs destinations, applies quotas, and rejects unknown hosts.

### 5. Narrow, short-lived credentials

The AI job receives no standing production or administrative credential. Prefer
short-lived workload identity and a dedicated bot identity.

The bot identity should be able to:

- read the required repository content;
- write only to the intended test-branch namespace;
- create or update its remediation pull request;
- publish the minimum evidence required by CI.

It should not be able to:

- edit repository settings or branch protections;
- approve or merge pull requests;
- read unrelated repository or environment secrets;
- publish a production artifact;
- deploy to staging or production;
- create or approve an exception.

The model credential itself is still sensitive. Isolate it from tested subprocesses
where possible, apply spend and request limits, and prevent it from being reused
outside the controlled job.

### 6. Independent deterministic validation

The model must not decide whether its patch passed.

A clean CI job should:

1. check out the exact AI commit;
2. load checks and policy from a trusted source;
3. install dependencies reproducibly;
4. verify that protected files were not modified;
5. run required tests and security scans;
6. validate coverage and test integrity;
7. publish machine-readable evidence;
8. make the pass/fail decision without model interpretation.

Where test manipulation is a concern, preserve independent acceptance tests outside
the AI-writable checkout or compare required tests against the approved baseline.

### 7. Bounded repair loops

Every invocation needs hard limits:

- maximum attempts;
- maximum agent turns and tool calls;
- wall-clock timeout;
- token and spend budget;
- maximum changed files and lines;
- maximum generated artifact size;
- approved command and tool list;
- concurrency and environment quotas.

Repeated failure, ambiguous requirements, protected-file changes, security-sensitive
code, or a threshold-exceeding diff must stop automation and escalate.

## Safe, conditional, and prohibited autonomy

### Generally safe within containment

- Formatting, lint, and type-check corrections
- Narrow application-code fixes with deterministic tests
- Documentation and generated metadata
- Test-fixture updates that do not redefine acceptance criteria
- Failure classification and evidence-linked summaries
- Remediation pull-request creation

### Conditional and higher scrutiny

- Dependency and lockfile changes
- Authentication, authorization, cryptography, or privacy-sensitive code
- Data migrations and stateful behavior
- Infrastructure and deployment manifests
- Build-system or compiler configuration
- Concurrency, performance, or distributed-system fixes
- Broad refactors
- Any change that alters an external contract

These changes may still be drafted by AI, but should stop after proposal or receive
stronger independent tests and review.

### Prohibited autonomous actions

- Modifying the controls used to judge the change
- Disabling or suppressing required tests and scanners
- Weakening coverage or stop-ship thresholds
- Accessing production data or credentials
- Approving or merging its own change
- Granting itself additional tools, files, network destinations, or identities
- Deploying around a protected environment
- Creating, approving, or extending a policy exception
- Automatically closing a security finding without independent evidence

## Test integrity and reward-hacking risks

An agent asked only to “make CI green” may satisfy the literal objective by changing
the test rather than correcting the behavior. The repair prompt and external policy
must define success as preserving the acceptance contract.

Controls include:

- prohibit deletion or weakening of existing required tests;
- compare test files and coverage with the approved baseline;
- keep critical acceptance and security tests outside the writable checkout;
- require explicit justification for every test change;
- distinguish implementation fixes from acceptance-criteria changes;
- rerun all required checks after the remediation pull request is opened;
- treat suspiciously large reductions in code, assertions, coverage, or scan scope as
  policy failures.

## Prompt-injection and untrusted-input risks

Repository files, issue text, pull-request comments, logs, test output, dependency
metadata, and downloaded documentation are untrusted model input. Any of them may
contain instructions intended to redirect the agent.

Mitigations include:

- clearly delimit evidence from system instructions;
- expose actions through small typed tools instead of unrestricted shell access;
- use permission deny rules and OS-enforced isolation;
- validate all structured model output;
- prevent logs or repository text from changing tool permissions;
- redact credentials and sensitive data before model access;
- maintain an outbound network allowlist;
- block or separately approve unsandboxed execution;
- keep the final control decision outside the model.

Prompt filtering alone is not sufficient. The design assumes that model behavior may
be manipulated and limits the damage that manipulated behavior can cause.

## Test, staging, and production separation

The three environments have different purposes:

| Environment | Purpose | AI authority |
|---|---|---|
| Disposable test | Fast experimentation and repair | May deploy with narrow, expiring access |
| Protected staging | Production-equivalent verification | No direct promotion; may summarize evidence |
| Production | Operate an approved release bundle | No authorization or standing credentials |

Staging should use production-equivalent deployment mechanics, configuration shape,
security controls, observability, and recovery procedures. It must remain separate in
credentials, data, external integrations, network trust, and administrative authority.

The desired relationship is **production-like, not production-connected**.

## Control-framework alignment

AI-assisted changes remain ordinary software changes for control purposes. Automation
does not remove the need to demonstrate that access is appropriate, changes are
authorized and tested, sensitive information is protected, and control operation is
monitored.

For a SOC 2-oriented control environment, the design can contribute evidence for:

| Control concern | Evidence from this design |
|---|---|
| Risk assessment | Documented autonomy levels, threat model, protected change classes, and residual risks |
| Logical access | Dedicated bot identity, least privilege, short-lived credentials, and periodic access review |
| Change management | Source commit, AI attempts, remediation pull request, clean CI, and independent approval |
| Processing integrity | Deterministic test results, protected acceptance evidence, immutable artifacts, and deployment verification |
| Confidentiality and privacy | Data classification, model-provider policy, redaction, isolation, egress controls, and retention rules |
| Monitoring | Tool-call logs, permission violations, security findings, escalations, and incident records |
| Availability | Bounded resource use, model-unavailable fallback, suspension controls, and tested recovery |

The exact evidence and retention requirements must come from the applicable control
description and assessment scope. A compliance report does not make unrestricted AI
safe; it evaluates whether the stated controls are suitably designed and operating.

## Data handling

Before enabling AI automation, classify what may enter model context:

- source and generated code;
- CI logs and stack traces;
- issue and pull-request content;
- configuration and infrastructure definitions;
- telemetry samples;
- test fixtures and database extracts;
- secret-scanner and vulnerability results.

Define approved model providers, retention settings, regions, encryption requirements,
telemetry policy, and prohibited data classes. Use synthetic or sanitized test data.
Never assume that masking in CI logs is a complete data-loss-prevention control.

## Audit evidence

Each autonomous attempt should record:

- initiating event and source commit;
- bot identity and effective permissions;
- runner image and isolation policy version;
- model and versioned prompt or instruction set;
- evidence supplied to the model;
- tool calls, commands, network destinations, and exit statuses;
- files and lines changed;
- attempt number, time, tokens, and cost;
- local validation results;
- independent CI and security results;
- remediation pull-request identity;
- approval, rejection, escalation, or exception outcome.

Sensitive prompt and response data may need restricted access and a different retention
period from normal CI logs. The audit record should reference protected evidence rather
than duplicating secrets or sensitive content.

## Example policy manifest

This is conceptual rather than tied to one implementation:

```yaml
ai_repair:
  enabled: true
  writable_branch_pattern: "ai-test/**"
  output: remediation_pull_request

  limits:
    attempts: 3
    turns_per_attempt: 8
    timeout_minutes: 20
    changed_files: 12
    changed_lines: 500

  filesystem:
    allow_write:
      - "app/**"
      - "src/**"
    deny_write:
      - ".github/**"
      - "CODEOWNERS"
      - "policies/**"
      - "production/**"

  network:
    default: deny
    allowed_purposes:
      - model_api
      - approved_dependency_registry

  credentials:
    repository_admin: none
    staging: none
    production: none

  validation:
    trusted_workflow_ref: "central/ci/ai-repair@immutable-revision"
    protected_test_baseline: true
    require_clean_ci: true
    require_independent_review: true
```

The policy must be enforced by the execution platform. A repository file editable by
the agent cannot be the sole authority for its own restrictions.

## Adoption stages

Introduce autonomy incrementally:

1. **Observe:** AI reads failures and produces summaries only.
2. **Suggest:** AI generates a patch artifact without repository write access.
3. **Branch write:** AI commits to a disposable branch and opens a pull request.
4. **Bounded repair:** AI retries failed test-branch runs within strict limits.
5. **Selective expansion:** Additional change classes become eligible based on measured
   safety, acceptance, and incident history.

Do not begin with unrestricted autonomous repair. Each stage should have explicit entry,
exit, rollback, and suspension criteria.

## Measures of effectiveness

Track whether the system improves delivery without weakening controls:

- percentage of suggested patches accepted;
- percentage accepted without later correction;
- escaped-defect and rollback rate for AI-authored changes;
- security findings introduced or resolved;
- attempts and time per successful repair;
- CI time, queue time, and model cost;
- protected-path and permission violations;
- test-integrity violations;
- escalation and false-success rate;
- time saved from failure to approved remediation.

Do not optimize for “green builds” alone. A fast green result is harmful if it comes
from weakened tests, hidden findings, or broader authority.

## Minimum production-readiness checklist

- [ ] Trusted workflow definition cannot be changed by the AI branch.
- [ ] Default, feature, staging, and production paths are protected.
- [ ] AI identity cannot approve, merge, administer, or deploy.
- [ ] Runner is ephemeral and isolated from trusted runners.
- [ ] Filesystem and network policies are enforced outside the model.
- [ ] Protected paths and test-integrity rules are defined.
- [ ] No production credentials, data, or network path is available.
- [ ] Model credentials are scoped, monitored, and budget-limited.
- [ ] Repair attempts, time, diff size, and spend are bounded.
- [ ] Clean deterministic CI reruns every required gate.
- [ ] Staging is production-like but separately authorized and isolated.
- [ ] Audit evidence and data-retention rules are documented.
- [ ] Failure, escalation, suspension, and recovery paths have been exercised.

## References

- [Ideal Standard Software Delivery Flow](IDEAL_FLOW.md)
- [GitHub Actions secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub: compromised runners](https://docs.github.com/en/actions/concepts/security/compromised-runners)
- [GitHub: protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub: deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Claude Code: security](https://code.claude.com/docs/en/security)
- [Claude Code: sandboxing](https://code.claude.com/docs/en/sandboxing)
- [Claude Code: permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code: data usage](https://code.claude.com/docs/en/data-usage)
- [NIST Secure Software Development Framework](https://csrc.nist.gov/projects/ssdf)
- [NIST secure DevSecOps practices](https://pages.nist.gov/nccoe-devsecops/introduction.html)
- [AICPA SOC resource library](https://www.aicpa-cima.com/soc)
