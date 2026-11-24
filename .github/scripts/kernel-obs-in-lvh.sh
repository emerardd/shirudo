#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo

set -eu

cd /host
mode=$(cat build/kernel-obs-mode)
version=$(cat build/kernel-obs-version)
test -n "$version"

apt-get update
if ! DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Use-Pty=0 \
	install -y /host/upstream/shirudo-deb/shirudo-operator_*.deb; then
	/bin/sh /host/.github/scripts/kernel-obs-apt-diagnostics.sh
	exit 1
fi

case "$mode" in
preview)
	keys_dir=/host/.ci/kernel-obs-preview-keys
	trap 'rm -rf "$keys_dir"' EXIT
	install -d -m 0700 "$keys_dir"
	/usr/bin/shirudo genkey --keys-dir "$keys_dir"
	;;
publish)
	keys_dir=/host/.ci/kernel-obs-keys
	test -s "$keys_dir/signing_key.pem"
	test -s "$keys_dir/cert.der"
	;;
*)
	echo "unsupported kernel-obs build mode: $mode" >&2
	exit 1
	;;
esac

/usr/bin/shirudo bpm build /host/upatches/kernel-obs \
	--version "$version" \
	--keys-dir "$keys_dir" \
	--vmlinux /host/upstream/bpf-next-vmlinux-h/vmlinux.h

package="/host/kernel-obs-$version.bee"
test -s "$package"
/usr/bin/shirudo bpm info "$package"

case "$mode" in
preview)
	install -d -m 0755 /host/kernel-obs-preview
	cp "$package" /host/kernel-obs-preview/
	install -m 0644 "$keys_dir/cert.der" /host/kernel-obs-preview/cert.der
	;;
publish)
	install -d -m 0755 /etc/shirudo
	printf '%s\n' 'tls.classical_hosts = ghcr.io' > /etc/shirudo/shirudo.conf
	/usr/bin/shirudo config
	{
		IFS= read -r BPM_OCI_USERNAME
		IFS= read -r BPM_OCI_PASSWORD
	} < /host/.ci/kernel-obs-registry-credentials
	export BPM_OCI_USERNAME BPM_OCI_PASSWORD
	/usr/bin/shirudo bpm push "$package" \
		oci://ghcr.io/shirudo-dev/kernel-obs \
		--keys-dir "$keys_dir"
	;;
esac
