#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
SOURCE_KSMANAGER="${REPO_ROOT}/ks-manage/ksmanager.sh"

if [[ ! -f "${SOURCE_KSMANAGER}" ]]; then
	echo "[FAIL] Cannot find ${SOURCE_KSMANAGER}"
	exit 1
fi

TEST_ROOT=$(mktemp -d /tmp/ksmanager-dev-tests.XXXXXX)
MOCK_BIN="${TEST_ROOT}/mock-bin"
SANDBOX_HUB="${TEST_ROOT}/server-hub"
RUN_ID=$(basename "${TEST_ROOT}")
TMP_INFRA_HOST="tmp/${RUN_ID}"
LAB_ROOT="/${TMP_INFRA_HOST}"
KSMANAGER_HUB_DIR="${LAB_ROOT}/ksmanager-hub"
IPXE_DIR="${LAB_ROOT}/ipxe"

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
	rm -rf "${TEST_ROOT}"
	rm -rf "${KSMANAGER_HUB_DIR}" "${IPXE_DIR}" "${LAB_ROOT}/almalinux-latest"
}
trap cleanup EXIT

assert_true() {
	local msg="$1"
	shift
	if "$@"; then
		echo "[PASS] ${msg}"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		echo "[FAIL] ${msg}"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

assert_eq() {
	local msg="$1"
	local actual="$2"
	local expected="$3"
	if [[ "${actual}" == "${expected}" ]]; then
		echo "[PASS] ${msg}"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		echo "[FAIL] ${msg} (expected='${expected}', actual='${actual}')"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

make_mock_bin() {
	mkdir -p "${MOCK_BIN}"

	cat > "${MOCK_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "awk" ]] && printf '%s\n' "$*" | grep -q '/etc/shadow'; then
	echo '$6$devtest$mocked_shadow_hash'
	exit 0
fi
exec "$@"
EOF

	cat > "${MOCK_BIN}/dig" <<'EOF'
#!/usr/bin/env bash
last=""
rtype="A"
for a in "$@"; do
	if [[ "$a" == "A" || "$a" == "AAAA" ]]; then
		rtype="$a"
	fi
	last="$a"
done
if [[ "$rtype" == "AAAA" ]]; then
	echo "2001:db8::100"
else
	echo "192.0.2.100"
fi
EOF

	cat > "${MOCK_BIN}/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

	cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "is-active" ]]; then
	exit 1
fi
exit 0
EOF

	cat > "${MOCK_BIN}/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

	cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

	cat > "${MOCK_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
cat
EOF

	cat > "${MOCK_BIN}/rsync" <<'EOF'
#!/usr/bin/env bash
set -u
delete=false
args=()
for a in "$@"; do
	case "$a" in
		-a|-q)
			;;
		--delete)
			delete=true
			;;
		*)
			args+=("$a")
			;;
	esac
done

argc=${#args[@]}
if [[ $argc -lt 2 ]]; then
	exit 0
fi

dest="${args[$((argc-1))]}"
src_count=$((argc-1))

is_dir_dest=false
if [[ "${dest}" == */ ]] || [[ $src_count -gt 1 ]]; then
	is_dir_dest=true
fi

if $is_dir_dest; then
	mkdir -p "${dest}"
	if $delete; then
		rm -rf "${dest}"/*
	fi
fi

for ((i=0; i<src_count; i++)); do
	src="${args[$i]}"
	if [[ -d "${src}" ]]; then
		if $is_dir_dest; then
			cp -a "${src}"/. "${dest}"/ 2>/dev/null || true
		else
			mkdir -p "$(dirname "${dest}")"
			cp -a "${src}" "${dest}" 2>/dev/null || true
		fi
	elif [[ -f "${src}" ]]; then
		if $is_dir_dest; then
			cp -a "${src}" "${dest}"/ 2>/dev/null || true
		else
			mkdir -p "$(dirname "${dest}")"
			cp -a "${src}" "${dest}" 2>/dev/null || true
		fi
	else
		if $is_dir_dest; then
			mkdir -p "${dest}"
			touch "${dest}/$(basename "${src}")"
		else
			mkdir -p "$(dirname "${dest}")"
			touch "${dest}"
		fi
	fi
done
EOF

	chmod +x "${MOCK_BIN}"/*
}

setup_sandbox() {
	mkdir -p "${SANDBOX_HUB}/common-utils"
	mkdir -p "${SANDBOX_HUB}/ks-manage/ks-templates"
	mkdir -p "${SANDBOX_HUB}/ks-manage/ipxe-templates"
	mkdir -p "${SANDBOX_HUB}/ks-manage/addons-for-kickstarts"
	mkdir -p "${SANDBOX_HUB}/ks-manage/golden-boot-templates"
	mkdir -p "${SANDBOX_HUB}/named-manage"
	mkdir -p "${TEST_ROOT}/etc"

	cat > "${SANDBOX_HUB}/common-utils/color-functions.sh" <<'EOF'
#!/usr/bin/env bash
print_info() { echo "[INFO] $*"; }
print_error() { echo "[ERROR] $*" >&2; }
print_warning() { echo "[WARN] $*"; }
print_success() { echo "[OK] $*"; }
print_task() { echo "[TASK] $*"; }
print_task_done() { echo "[TASK] done"; }
print_task_fail() { echo "[TASK] fail"; }
print_notify() { echo "$*"; }
print_green() { echo "$*"; }
print_yellow() { echo "$*"; }
EOF

	cat > "${SANDBOX_HUB}/ks-manage/distro-versions.conf" <<'EOF'
#!/usr/bin/env bash
declare -A DISTRO_LATEST_VERSIONS=(
	[almalinux]="10"
	[rocky]="10"
	[oraclelinux]="9"
	[centos-stream]="10"
	[rhel]="10"
	[ubuntu-lts]="24.04"
	[opensuse-leap]="15.6"
)
declare -A DISTRO_PREVIOUS_VERSIONS=(
	[almalinux]="9"
	[rocky]="9"
	[oraclelinux]="8"
	[centos-stream]="9"
	[rhel]="9"
	[ubuntu-lts]="22.04"
	[opensuse-leap]="15.5"
)
EOF

	cat > "${SANDBOX_HUB}/ks-manage/ks-templates/redhat-based-latest-ks.cfg" <<'EOF'
hostname=get_hostname
domain=get_ipv4_domain
gw=get_ipv4_gateway
EOF

	cat > "${SANDBOX_HUB}/ks-manage/ipxe-templates/ipxe-template-redhat-based-auto-latest.ipxe" <<'EOF'
#!ipxe
set host get_hostname
set domain get_ipv4_domain
EOF

	cat > "${SANDBOX_HUB}/ks-manage/golden-boot-templates/golden-boot.service" <<'EOF'
[Unit]
Description=golden-boot
EOF

	cat > "${SANDBOX_HUB}/ks-manage/golden-boot-templates/golden-boot.sh" <<'EOF'
#!/usr/bin/env bash
echo golden
EOF

	cat > "${SANDBOX_HUB}/ks-manage/golden-boot-templates/network-config-for-mac-address" <<'EOF'
HOST=get_hostname
EOF

	cat > "${SANDBOX_HUB}/named-manage/dnsbinder.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${SANDBOX_HUB}/named-manage/dnsbinder.sh"

	cp "${SOURCE_KSMANAGER}" "${SANDBOX_HUB}/ks-manage/ksmanager.sh"
	sed -i "s|^source /etc/environment|source ${TEST_ROOT}/etc/environment|" "${SANDBOX_HUB}/ks-manage/ksmanager.sh"
	sed -i "s|/server-hub|${SANDBOX_HUB}|g" "${SANDBOX_HUB}/ks-manage/ksmanager.sh"
	chmod +x "${SANDBOX_HUB}/ks-manage/ksmanager.sh"

	cat > "${TEST_ROOT}/etc/environment" <<EOF
mgmt_super_user=${USER}
dnsbinder_server_ipv4_address=192.0.2.53
dnsbinder_server_ipv6_address=2001:db8::53
dnsbinder_domain=example.test
dnsbinder_network_cidr=192.0.2.0/24
dnsbinder_netmask=255.255.255.0
dnsbinder_cidr_prefix=24
dnsbinder_gateway=192.0.2.1
dnsbinder_server_fqdn=${TMP_INFRA_HOST}
dnsbinder_first24_subnet=192.0.2.10
dnsbinder_last24_subnet=192.0.2.20
dnsbinder_ipv6_gateway=
dnsbinder_ipv6_prefix=64
dnsbinder_ipv6_ula_subnet=fd00:1::/64
EOF

	mkdir -p "${LAB_ROOT}/almalinux-latest"
	printf 'AlmaLinux Mock\n' > "${LAB_ROOT}/almalinux-latest/.discinfo"
}

run_ksmanager() {
	PATH="${MOCK_BIN}:$PATH" USER="${USER}" bash "${SANDBOX_HUB}/ks-manage/ksmanager.sh" "$@"
}

test_create_host_noninteractive() {
	local host="node1.example.test"
	local mac="aa:bb:cc:dd:ee:01"
	local mac_ipxe="aa-bb-cc-dd-ee-01"

	run_ksmanager "${host}" --distro almalinux --version latest --mac "${mac}" --qemu-kvm >"${TEST_ROOT}/ksmanager_test_create.log" 2>&1
	local rc=$?
	assert_eq "create-host exits 0" "${rc}" "0"

	assert_true "mac cache exists" test -f "${KSMANAGER_HUB_DIR}/mac-address-cache"
	assert_true "cache contains host" grep -q "^${host} " "${KSMANAGER_HUB_DIR}/mac-address-cache"
	assert_true "kickstart file created" test -f "${KSMANAGER_HUB_DIR}/kickstarts/${host}/redhat-based-latest-ks.cfg"
	assert_true "ipxe file created" test -f "${IPXE_DIR}/${mac_ipxe}.ipxe"
	assert_true "hostname token replaced" grep -q "hostname=node1" "${KSMANAGER_HUB_DIR}/kickstarts/${host}/redhat-based-latest-ks.cfg"
}

test_parallel_same_host_single_cache_row() {
	local host="node2.example.test"

	run_ksmanager "${host}" --distro almalinux --version latest --mac aa:bb:cc:dd:ee:02 --qemu-kvm >"${TEST_ROOT}/ksmanager_test_p1.log" 2>&1 &
	local p1=$!
	run_ksmanager "${host}" --distro almalinux --version latest --mac aa:bb:cc:dd:ee:03 --qemu-kvm >"${TEST_ROOT}/ksmanager_test_p2.log" 2>&1 &
	local p2=$!
	wait "$p1"
	local r1=$?
	wait "$p2"
	local r2=$?

	assert_eq "parallel run #1 exits 0" "${r1}" "0"
	assert_eq "parallel run #2 exits 0" "${r2}" "0"

	local rows
	rows=$(grep -c "^${host} " "${KSMANAGER_HUB_DIR}/mac-address-cache")
	assert_eq "single cache row for same host" "${rows}" "1"
}

test_parallel_remove_host_safe() {
	local host="node3.example.test"

	run_ksmanager "${host}" --distro almalinux --version latest --mac aa:bb:cc:dd:ee:04 --qemu-kvm >"${TEST_ROOT}/ksmanager_test_seed.log" 2>&1

	run_ksmanager "${host}" --remove-host >"${TEST_ROOT}/ksmanager_test_rm1.log" 2>&1 &
	local p1=$!
	run_ksmanager "${host}" --remove-host >"${TEST_ROOT}/ksmanager_test_rm2.log" 2>&1 &
	local p2=$!
	wait "$p1"
	local r1=$?
	wait "$p2"
	local r2=$?

	assert_eq "remove-host run #1 exits 0" "${r1}" "0"
	assert_eq "remove-host run #2 exits 0" "${r2}" "0"

	local rows
	rows=$(grep -c "^${host} " "${KSMANAGER_HUB_DIR}/mac-address-cache" 2>/dev/null || true)
	assert_eq "host removed from cache" "${rows}" "0"
	assert_true "no cache lock dir remains" test ! -d "${KSMANAGER_HUB_DIR}/.mac-address-cache.lock"
	assert_true "no shared lock dir remains" test ! -d "${KSMANAGER_HUB_DIR}/.shared-artifacts.lock"
}

echo "[INFO] Setting up sandbox under ${TEST_ROOT}"
make_mock_bin
setup_sandbox

test_create_host_noninteractive
test_parallel_same_host_single_cache_row
test_parallel_remove_host_safe

echo "[INFO] PASS=${PASS_COUNT} FAIL=${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -ne 0 ]]; then
	exit 1
fi

echo "[OK] All ksmanager dev tests passed"
exit 0
