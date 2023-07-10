#!/usr/bin/env bash

set -e

ACTION_DIR="$(cd $(dirname "${BASH_SOURCE[0]}") >/dev/null 2>&1 && pwd)"

function usage {
	echo "Usage: ${0} --command=[start|stop] <arguments>"
}

function safety_on {
	set -o errexit -o pipefail -o noclobber -o nounset
}

function safety_off {
	set +o errexit +o pipefail +o noclobber +o nounset
}

source "${ACTION_DIR}/vendor/getopts_long.sh"

command=
token=
project_id=
runner_ver=
machine_zone=
machine_type=
boot_disk_type=
disk_size=
runner_service_account=
image_project=
image=
image_family=
scopes=
shutdown_timeout=
preemptible=
ephemeral=
maintenance_policy_terminate=

OPTLIND=1
while getopts_long :h opt \
	command required_argument \
	token required_argument \
	project_id required_argument \
	runner_ver required_argument \
	machine_zone required_argument \
	machine_type required_argument \
	boot_disk_type optional_argument \
	disk_size optional_argument \
	runner_service_account optional_argument \
	image_project optional_argument \
	image optional_argument \
	image_family optional_argument \
	scopes required_argument \
	shutdown_timeout required_argument \
	preemptible required_argument \
	ephemeral required_argument \
	maintenance_policy_terminate optional_argument \
	help no_argument "" "$@"; do
	case "$opt" in
	command)
		command=$OPTLARG
		;;
	token)
		token=$OPTLARG
		;;
	project_id)
		project_id=$OPTLARG
		;;
	runner_ver)
		runner_ver=$OPTLARG
		;;
	machine_zone)
		machine_zone=$OPTLARG
		;;
	machine_type)
		machine_type=$OPTLARG
		;;
	boot_disk_type)
		boot_disk_type=${OPTLARG-$boot_disk_type}
		;;
	disk_size)
		disk_size=${OPTLARG-$disk_size}
		;;
	runner_service_account)
		runner_service_account=${OPTLARG-$runner_service_account}
		;;
	image_project)
		image_project=${OPTLARG-$image_project}
		;;
	image)
		image=${OPTLARG-$image}
		;;
	image_family)
		image_family=${OPTLARG-$image_family}
		;;
	scopes)
		scopes=$OPTLARG
		;;
	shutdown_timeout)
		shutdown_timeout=$OPTLARG
		;;
	preemptible)
		preemptible=$OPTLARG
		;;
	ephemeral)
		ephemeral=$OPTLARG
		;;
	maintenance_policy_terminate)
		maintenance_policy_terminate=${OPTLARG-$maintenance_policy_terminate}
		;;
	h | help)
		usage
		exit 0
		;;
	:)
		printf >&2 '%s: %s\n' "${0##*/}" "$OPTLERR"
		usage
		exit 1
		;;
	esac
done

function start_vm {
	echo "Starting GCE VM ..."
	RUNNER_TOKEN=$(curl -S -s -XPOST \
		-H "authorization: Bearer ${token}" \
		"https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" |
		jq -r .token)
	echo "✅ Successfully got the GitHub Runner registration token"

	VM_ID="gce-gh-runner-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
	image_project_flag=$([[ -z "${image_project}" ]] || echo "--image-project=${image_project}")
	image_flag=$([[ -z "${image}" ]] || echo "--image=${image}")
	image_family_flag=$([[ -z "${image_family}" ]] || echo "--image-family=${image_family}")
	disk_size_flag=$([[ -z "${disk_size}" ]] || echo "--boot-disk-size=${disk_size}")
	boot_disk_type_flag=$([[ -z "${boot_disk_type}" ]] || echo "--boot-disk-type=${boot_disk_type}")
	preemptible_flag=$([[ "${preemptible}" == "true" ]] && echo "--preemptible" || echo "")
	ephemeral_flag=$([[ "${ephemeral}" == "true" ]] && echo "--ephemeral" || echo "")
	maintenance_policy_flag=$([[ -z "${maintenance_policy_terminate}" ]] || echo "--maintenance-policy=TERMINATE")
	project_id_flag=$(echo "--project=${project_id}")

	echo "The new GCE VM will be ${VM_ID}"

	startup_script=$(
		cat <<OUT_EOF
#!/bin/bash

set -e
set -x

gcloud compute instances add-labels "${VM_ID}" --zone="${machine_zone}" --labels=gh_ready=0

chmod 777 /var/tmp
chmod 777 -R /var/tmp

# Create a systemd service in charge of shutting down the machine once the workflow has finished
cat <<-EOF >/etc/systemd/system/shutdown.sh
	#!/bin/sh
	sleep "${shutdown_timeout}"
	gcloud compute instances delete "${VM_ID}" --zone="${machine_zone}" --quiet
EOF

chmod +x /etc/systemd/system/shutdown.sh

su -s /bin/bash -c "cd /actions-runner/;/actions-runner/config.sh --url https://github.com/${GITHUB_REPOSITORY} --token ${RUNNER_TOKEN} --labels ${VM_ID} --unattended ${ephemeral_flag} --disableupdate" runner

touch /.github-runner-config-ready

gcloud compute instances add-labels "${VM_ID}" --zone="${machine_zone}" --labels=gh_ready=1
echo "Setup complete."

OUT_EOF
	)

	shutdown_script=$(
		cat <<OUT_EOF
#!/bin/bash

set -e
set -x

pushd /actions-runner || exit 1

REMOVE_TOKEN=\$(curl -s -X POST https://api.github.com/repos/"${GITHUB_REPOSITORY}"/actions/runners/remove-token -H "accept: application/vnd.github.everest-preview+json" -H "authorization: token ${RUNNER_TOKEN}" | jq -r '.token')
if [ -z "\$REMOVE_TOKEN" ]; then 
	fatal "Failed to get a token";
fi 

./config.sh remove --token \$REMOVE_TOKEN

OUT_EOF
	)

	gcloud compute instances create "${VM_ID}" \
		${project_id_flag} \
		--zone="${machine_zone}" \
		${disk_size_flag} \
		${boot_disk_type_flag} \
		--machine-type="${machine_type}" \
		--scopes="${scopes}" \
		${image_project_flag} \
		${image_flag} \
		${image_family_flag} \
		${preemptible_flag} \
		${maintenance_policy_flag} \
		--labels=gh_ready=0 \
		--metadata=startup-script="$startup_script,shutdown-script=$shutdown_script" &&
		echo "label=${VM_ID}" >>"${GITHUB_OUTPUT}"

	safety_off
	while ((i++ < 60)); do
		GH_READY=$(gcloud compute instances describe "${VM_ID}" --zone="${machine_zone}" --format='json(labels)' | jq -r .labels.gh_ready)
		if [[ $GH_READY == 1 ]]; then
			break
		fi
		echo "${VM_ID} not ready yet, waiting 5s ..."
		sleep 5
	done
	if [[ $GH_READY == 1 ]]; then
		echo "✅ ${VM_ID} ready ..."
	else
		echo "Waited 5 minutes for ${VM_ID}, without luck, deleting ${VM_ID} ..."
		gcloud --quiet compute instances delete "${VM_ID}" --zone="${machine_zone}"
		exit 1
	fi
}

safety_on
case "$command" in
start)
	start_vm
	;;
*)
	echo "Invalid command: \`${command}\`, valid values: start" >&2
	usage
	exit 1
	;;
esac
