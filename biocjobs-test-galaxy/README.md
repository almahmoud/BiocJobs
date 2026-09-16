# biocjobs-test-galaxy

Tool wrappers for the Bioc jobs test Galaxy at https://testgalaxy.bioconductor.org.

Open a pull request that adds a wrapper. A maintainer deploys it to the test Galaxy,
where you can run it without signing in (two jobs at a time, 5 GB of storage).
Merged tools stay deployed. Closing a pull request removes its tools.

## Adding a tool

Create `tools/<tool_id>/<tool_id>.xml`. [examples/hello_world](examples/hello_world/hello_world.xml)
is a working starting point.

- The tool id is 2 to 32 lowercase letters, digits or underscores, starts with a letter,
  and matches the directory and file name.
- The wrapper is one file of at most 64 KB. Macro imports and `$__tool_directory__`
  scripts are not available.
- The tool declares one Docker container, and the image has `/bin/bash`. BioContainers,
  Debian and Ubuntu images work; `busybox` and `alpine` do not.
- `profile`, if set, is 24.1 or lower.
- Interactive and data source tools are not supported.
- Jobs can reach the internet, but not anything hosted on the cluster, including this Galaxy.

Increase `version` each time you change a tool.

**Validate tools** checks these rules, runs `planemo lint`, and checks each container
for bash. If `main` changes a tool after your branch was created, rebase before asking
for a deploy.

## Commands

Maintainers with write access comment on the pull request:

| Command | |
|---|---|
| `/deploy <sha>` | Deploy the pull request at commit `<sha>`, which must be its latest commit. |
| `/undeploy` | Remove the pull request's tools from the test Galaxy. |
| `/help` | List the commands. |

New commits remove a deployed pull request until it is deployed again. Deployed pull
requests have the `deployed` label.

## Setup

With cluster admin credentials:

```bash
kubectl apply -f deploy/namespace-setup.yaml
deploy/make-kubeconfig.sh
gh api -X PUT repos/{owner}/{repo}/environments/testgalaxy
gh secret set KUBECONFIG --env testgalaxy < galaxy-deployer.kubeconfig
rm galaxy-deployer.kubeconfig
```

Galaxy settings are in [deploy/values.yaml](deploy/values.yaml). Settings missing from
that file return to the chart defaults on the next deploy. To redeploy without a change,
run the **Deploy to test instance** workflow.
