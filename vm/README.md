# VM

For more context see [Running Github runners in GCE VMs](https://www.notion.so/gitpod/Running-Github-runners-in-GCE-VMs-6ccd9c876abb4061b62671548279bca7) especially [How can I update the GCP VM image?](https://www.notion.so/gitpod/Running-Github-runners-in-GCE-VMs-6ccd9c876abb4061b62671548279bca7?pvs=4#5403e37be74342e48c25242aa2d946c5).

```sh
gcloud auth application-default login --no-launch-browser
gcloud auth login --no-launch-browser
gcloud config set project public-github-runners
cd vm
make build-actions-runner-image
```