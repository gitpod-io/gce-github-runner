# gce-github-runner

Ephemeral GCE GitHub self-hosted runner based on https://github.com/related-sciences/gce-github-runner

For more context see [Running Github runners in GCE VMs](https://www.notion.so/gitpod/Running-Github-runners-in-GCE-VMs-6ccd9c876abb4061b62671548279bca7)

## Usage

```yaml
jobs:
  create-runner:
    uses: gitpod-io/gce-github-runner/.github/workflows/create-vm.yml@secrets
    secrets:
      runner_token: ${{ secrets.GH_SA_TOKEN }}
      gcp_credentials: ${{ secrets.GCP_SA_KEY }}

  test:
    needs: [create-runner]
    runs-on: ${{ needs.create-runner.outputs.label }}
    steps:
      - run: echo "This runs on the GCE VM"

  delete-runner:
    if: always()
    needs:
      - create-runner
      - test
    uses: gitpod-io/gce-github-runner/.github/workflows/delete-vm.yml@secrets
    secrets:
      gcp_credentials: ${{ secrets.GCP_SA_KEY }}
    with:
      runner-label: ${{ needs.create-runner.outputs.label }}
      machine-zone: ${{ needs.create-runner.outputs.machine-zone }}
```

* `create-runner` creates the GCE VM and registers the runner with unique label
* `test` uses the runner
* `delete-runner` waits for the end of the steps execution and then shutdowns the GCE VM, removing the runner from the GitHub runner


## Inputs

See inputs and descriptions [here](./action.yml).
