# Connect GitHub to the SRE Agent

This guide connects a GitHub repository to your Azure SRE Agent. It is shared by every workshop
track — follow the parts your track's module points you to.

There are **two separate GitHub integrations**, and they do different jobs:

| Integration | Where you set it up | What it gives the agent |
| --- | --- | --- |
| **Code repository** | The **Code** card on the agent setup page | Reads your code for root-cause analysis (file/line references, deployment correlation) |
| **GitHub connector** | **Builder → Connectors** | Creates and reads **issues**, **pull requests**, and **workflow** runs |

Connecting the code repository automatically creates a GitHub OAuth connector for sign-in, but you
still add and verify the **GitHub connector** below before the agent can file issues.

> **Reference:** [Connect source code](https://learn.microsoft.com/azure/sre-agent/connect-source-code)
> and [Set up the GitHub connector](https://learn.microsoft.com/azure/sre-agent/setup-github-connector)
> (Azure SRE Agent documentation).

## Connect your code repository

On the agent setup page (click **Set up your agent** after deployment finishes):

1. On the **Code** card, click the **+** button.
2. Choose a platform: select **GitHub** (Azure DevOps is also supported).
3. Choose a sign-in method:
   - **Auth** (OAuth) — click **Sign in** and approve access in the browser popup.
   - **PAT** — paste a Personal Access Token with `repo` scope and click **Connect**.
4. Click **Next**.
5. Pick your repository from the dropdown (repos are listed as `owner/repo`, alphabetically).
   Select the **forked workshop repository** you created in Module 0.
6. Click **Add repository**.
7. Wait for the **Code** card to show a green checkmark.

The agent immediately starts indexing the repo to learn your architecture, deployment
configuration, and code patterns.

## Set up the GitHub connector

The connector is what lets the agent **create GitHub issues** (and open/read pull requests and read
workflow runs) during incident response.

1. Open your agent and go to **Builder → Connectors**.
2. Click **Add connector**.
3. Select **GitHub OAuth connector**.
4. Choose an authentication method:
   - **OAuth** — click **Sign in to GitHub** and complete the popup authorization.
   - **PAT** — paste a GitHub token with `repo` scope (needed for private repos) and click **Connect**.
5. Confirm the connector status shows **Connected**.

> **Popup blocked?** If the sign-in window doesn't appear, allow popups for `sre.azure.com` and retry.

## Verify the connection

Open a chat thread with the agent and run a prompt against your repo:

```text
List recent issues from <owner>/<repo> and summarize the top 3.
```

If the connector is working, the agent returns issues from your repository. You can also ask it to
create a test issue to confirm write access.

## Which tracks use the connector?

- **Issue-based remediation tracks** (AKS, App Service): the agent files a GitHub issue describing
  the root cause and assigns it to **`@copilot`**, which opens a fix PR. These tracks **require** the
  GitHub connector.
- **Approval-gated tracks** (VM): remediation runs through an approved script, not GitHub issues.
  These tracks only need the **code repository** connection — you can **skip the GitHub connector**.
