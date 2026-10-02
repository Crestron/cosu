#!/usr/bin/env bash
####################################################################################
# Regression test for INC0551283 (CWE-214): key passwords must never appear on an
# openssl command line (visible to every local user via `ps` or /proc/<pid>/cmdline).
#
# It also proves the tool still does its real job: the root -> intermediate (signer)
# -> leaf (device) chain it produces must be a valid PKI. A security fix that quietly
# breaks certificate generation is worse than the bug, so both are checked every run.
#
# How it works
#   * Copies the repo scripts to a scratch dir and drives the REAL functions
#     (gen_root, gen_signer, interactive_gen_device_csr, interactive_gen_device_cert)
#     non-interactively by piping the answers to stdin.
#   * Puts a spy `openssl` first on PATH. It records the exact argv of every call
#     (what `ps` would show) and then runs the real openssl. Recording argv is
#     deterministic; polling `ps` would be racy.
#   * Runs two scenarios: an easy password and a hostile one (spaces, $, quotes, *, ;)
#     which also guards against word-splitting/quoting bugs.
#
# Groups:  [A] no password on any command line   [B] output is a valid PKI
#          [C] harness sanity (the spy really saw every openssl subcommand)
#
# Usage: tests/test_password_exposure.sh        (COSU_TEST_KEEP=1 keeps the scratch dir)
# Exit:  0 all passed, 1 failures, 2 cannot run (e.g. openssl missing)
####################################################################################

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
O="$(command -v openssl)" || { echo "SKIP: openssl not found"; exit 2; }
command -v timeout >/dev/null || { echo "SKIP: 'timeout' not found"; exit 2; }

PASSES=0
FAILS=0
FAILED_NAMES=()

ok()  { PASSES=$((PASSES + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAILS=$((FAILS + 1)); FAILED_NAMES+=("$1"); printf '  FAIL  %s\n' "$1"; }
# check <name> <command...>      passes when the command succeeds
check()     { local n=$1; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
# check_not <name> <command...>  passes when the command fails
check_not() { local n=$1; shift; if "$@" >/dev/null 2>&1; then bad "$n"; else ok "$n"; fi; }

# ---------- small openssl helpers (use the real binary, never the spy) ----------
subj()     { "$O" x509 -noout -subject -in "$1" 2>/dev/null | sed 's/^subject= *//'; }
iss()      { "$O" x509 -noout -issuer  -in "$1" 2>/dev/null | sed 's/^issuer= *//'; }
has_ext()  { "$O" x509 -noout -ext "$2" -in "$1" 2>/dev/null | grep -q -- "$3"; }
cert_pub() { "$O" x509 -noout -pubkey -in "$1" 2>/dev/null; }
# key_pub <key> <password>  (password goes via env, as the fix does)
key_pub()  { KEYPW="$2" "$O" pkey -in "$1" -passin env:KEYPW -pubout 2>/dev/null; }
epoch()    { date -d "$("$O" x509 -noout "-$2" -in "$1" | cut -d= -f2)" +%s; }
nonempty_eq() { [ -n "$1" ] && [ "$1" = "$2" ]; }
lifetime_days_is() {   # <cert> <expected days>, +/- 1 day tolerance
    local d=$(( ($(epoch "$1" enddate) - $(epoch "$1" startdate)) / 86400 ))
    [ "$d" -ge $(($2 - 1)) ] && [ "$d" -le $(($2 + 1)) ]
}
valid_now() { [ "$(epoch "$1" startdate)" -le "$(date +%s)" ] && "$O" x509 -noout -checkend 0 -in "$1" >/dev/null; }
is_encrypted_key() { head -n 1 "$1" | grep -q 'BEGIN ENCRYPTED PRIVATE KEY'; }
key_opens()        { KEYPW="$2" "$O" pkey -in "$1" -passin env:KEYPW -noout; }

# ---------- one full scenario ----------
run_scenario() {
    local label=$1 rpw=$2 spw=$3 dpw=$4
    local WORK; WORK="$(mktemp -d)"
    # Git Bash on Windows runs a native openssl that cannot resolve MSYS paths like
    # /tmp/x when they are written inside ssl.cnf (database = ...). Use C:/... there.
    if command -v cygpath >/dev/null; then WORK="$(cygpath -m "$WORK")"; fi
    local OUT="$WORK/out" LOG="$WORK/openssl_argv.log" SHIM="$WORK/shim"
    local ROOT="$OUT/COSU_Root_Cert" SIGN="$OUT/COSU_Signing_Cert"
    local DEV="$OUT/COSU-DEMO-DEVICE" DEP="$OUT/deploy/COSU-DEMO-DEVICE"

    echo
    echo "=== Scenario: $label ==="

    # Scratch copy of the tool. settings.cnf comes from the shipped template.
    cp "$REPO"/*.sh "$REPO/template_for_settings.cnf" "$WORK/"
    sed -e "s|^output_folder=.*|output_folder=$OUT|" \
        -e 's|^ssldef_device_ip=.*|ssldef_device_ip="10.1.2.3"|' \
        "$WORK/template_for_settings.cnf" > "$WORK/settings.cnf"
    # cosu.sh minus its trailing `run` (which would start the interactive menu).
    sed '/^run[[:space:]]*$/d' "$WORK/cosu.sh" > "$WORK/cosu_lib.sh"

    # Spy openssl: log argv, then run the real thing. stdin is closed so openssl can
    # never swallow the answers we pipe to the script's own `read` prompts.
    mkdir -p "$SHIM"
    cat > "$SHIM/openssl" <<'EOF'
#!/usr/bin/env bash
{ printf 'openssl'; printf ' [%s]' "$@"; printf '\n'; } >> "$COSU_TEST_LOG"
exec "$COSU_REAL_OPENSSL" "$@" </dev/null
EOF
    chmod +x "$SHIM/openssl"
    # PATH is colon-separated, so a C:/... entry would be split; use the POSIX form.
    local SHIM_PATH="$SHIM"
    if command -v cygpath >/dev/null; then SHIM_PATH="$(cygpath -u "$SHIM")"; fi
    : > "$LOG"

    # step <name> <function> <stdin lines...>
    step() {
        local name=$1 fn=$2; shift 2
        printf '%s\n' "$@" | COSU_TEST_LOG="$LOG" COSU_REAL_OPENSSL="$O" PATH="$SHIM_PATH:$PATH" \
            timeout 300 bash -c "cd '$WORK' && source ./cosu_lib.sh && $fn" \
            > "$WORK/step_$name.log" 2>&1
        local rc=$?
        if [ $rc -eq 0 ]; then ok "[B] step $name ran to completion"; else
            bad "[B] step $name ran to completion (exit $rc; see $WORK/step_$name.log)"
            tail -n 5 "$WORK/step_$name.log" | sed 's/^/        | /'
        fi
    }

    # Answers, in the order each function reads them:
    #   gen_root:  pw, verify, <Enter for pause>, view? (n)
    #   gen_signer: pw, verify, <Enter>, ROOT pw, view? (n)
    #   csr:       pw, verify, view? (n)
    #   cert:      signer pw, device pw, view? (n)
    step root   gen_root                    "$rpw" "$rpw" "" n
    step signer gen_signer                  "$spw" "$spw" "" "$rpw" n
    step csr    interactive_gen_device_csr  "$dpw" "$dpw" n
    step cert   interactive_gen_device_cert "$spw" "$dpw" n

    # ----- [A] nothing sensitive on any command line -----
    # Hostile passwords contain spaces, so word splitting would scatter them across
    # argv; the last whitespace-free tail is still contiguous and unique.
    local pw needle
    for pw in "$rpw" "$spw" "$dpw"; do
        needle="${pw##* }"
        check_not "[A] argv log never contains password fragment '$needle'" grep -aqF -- "$needle" "$LOG"
    done
    check_not "[A] no openssl call uses a literal 'pass:' argument" grep -aqE '\[pass:' "$LOG"
    if grep -aqE '\[pass:' "$LOG"; then
        echo "      offending openssl calls (password redacted):"
        grep -aE '\[pass:' "$LOG" | sed 's/\[pass:[^]]*\]/[pass:<REDACTED>]/g; s/^/        | /' | cut -c1-110
    fi

    # ----- [C] harness sanity: the spy must have seen every subcommand -----
    local sub
    for sub in genpkey req ca rsa pkcs12; do
        check "[C] spy recorded at least one 'openssl $sub'" grep -aq "^openssl \[$sub\]" "$LOG"
    done

    # ----- [B] root -> intermediate -> leaf is a valid PKI -----
    local R="$ROOT/cert.pem" S="$SIGN/cert.pem" L="$DEV/cert.pem"
    local settings="$WORK/settings.cnf" dr di dl
    dr=$(sed -n 's/^sslrootdays="\(.*\)"/\1/p' "$settings")
    di=$(sed -n 's/^sslintdays="\(.*\)"/\1/p' "$settings")
    dl=$(sed -n 's/^sslsrvdays="\(.*\)"/\1/p' "$settings")

    check "[B] root, intermediate and leaf certificates exist" test -s "$R" -a -s "$S" -a -s "$L"

    # Root
    check "[B] root is self-signed (subject == issuer)"     nonempty_eq "$(subj "$R")" "$(iss "$R")"
    check "[B] root is a CA (basicConstraints CA:TRUE)"     has_ext "$R" basicConstraints 'CA:TRUE'
    check "[B] root may sign certs (keyUsage keyCertSign)"  has_ext "$R" keyUsage 'Certificate Sign'
    check "[B] root verifies against itself"                "$O" verify -CAfile "$R" "$R"
    check "[B] root lifetime is $dr days"                   lifetime_days_is "$R" "$dr"
    check "[B] root is currently valid"                     valid_now "$R"

    # Intermediate
    check "[B] intermediate issuer == root subject"         nonempty_eq "$(iss "$S")" "$(subj "$R")"
    check "[B] intermediate is a CA (CA:TRUE)"              has_ext "$S" basicConstraints 'CA:TRUE'
    check "[B] intermediate is path-length limited (pathlen:0)" has_ext "$S" basicConstraints 'pathlen:0'
    check "[B] intermediate verifies against root"          "$O" verify -CAfile "$R" "$S"
    check "[B] intermediate lifetime is $di days"           lifetime_days_is "$S" "$di"
    check "[B] intermediate is currently valid"             valid_now "$S"

    # Leaf
    check "[B] leaf issuer == intermediate subject"         nonempty_eq "$(iss "$L")" "$(subj "$S")"
    check "[B] leaf is not a CA (CA:FALSE)"                 has_ext "$L" basicConstraints 'CA:FALSE'
    check "[B] leaf is for TLS servers (serverAuth)"        has_ext "$L" extendedKeyUsage 'TLS Web Server Authentication'
    check "[B] leaf SAN has DNS:COSU-DEMO-DEVICE"           has_ext "$L" subjectAltName 'DNS:COSU-DEMO-DEVICE'
    check "[B] leaf SAN has IP Address:10.1.2.3"            has_ext "$L" subjectAltName 'IP Address:10.1.2.3'
    check "[B] leaf CN is COSU-DEMO-DEVICE"                 bash -c "'$O' x509 -noout -subject -in '$L' | grep -q 'CN *= *COSU-DEMO-DEVICE'"
    check "[B] leaf lifetime is $dl days"                   lifetime_days_is "$L" "$dl"
    check "[B] leaf is currently valid"                     valid_now "$L"

    # Chain
    check "[B] full chain verifies: root -> intermediate -> leaf"  "$O" verify -CAfile "$R" -untrusted "$S" "$L"
    check_not "[B] leaf does NOT verify against root alone (it was issued by the intermediate)" "$O" verify -CAfile "$R" "$L"
    MSYS2_ARG_CONV_EXCL='*' "$O" req -x509 -newkey rsa:2048 -nodes -subj "/CN=Unrelated CA" \
        -keyout "$WORK/other.key" -out "$WORK/other.pem" -days 2 >/dev/null 2>&1
    check "[B] harness built an unrelated CA for the negative test" test -s "$WORK/other.pem"
    check_not "[B] leaf does NOT verify against an unrelated CA" "$O" verify -CAfile "$WORK/other.pem" -untrusted "$S" "$L"

    # Key / certificate pairing and key protection, per tier
    local tier cert key pw
    for tier in root signer device; do
        case $tier in
            root)   cert=$R key="$ROOT/key.pem" pw=$rpw ;;
            signer) cert=$S key="$SIGN/key.pem" pw=$spw ;;
            device) cert=$L key="$DEV/key.pem"  pw=$dpw ;;
        esac
        check     "[B] $tier key is stored encrypted"             is_encrypted_key "$key"
        check     "[B] $tier key opens with its password"         key_opens "$key" "$pw"
        check_not "[B] $tier key rejects a wrong password"        key_opens "$key" "definitely-wrong"
        check     "[B] $tier key matches its certificate"         nonempty_eq "$(key_pub "$key" "$pw")" "$(cert_pub "$cert")"
    done

    # Deployment artifacts
    check "[B] deploy: rootCA_cert.cer is the root cert"          cmp -s "$R" "$DEP/rootCA_cert.cer"
    check "[B] deploy: intermediate_cert.cer is the signer cert"  cmp -s "$S" "$DEP/intermediate_cert.cer"
    check "[B] deploy: srv_cert.cer is the leaf cert"             cmp -s "$L" "$DEP/srv_cert.cer"
    check "[B] deploy: srv_key.pem parses and matches the leaf"   nonempty_eq "$("$O" pkey -in "$DEP/srv_key.pem" -pubout 2>/dev/null)" "$(cert_pub "$L")"
    check "[B] deploy: webserver_cert.pfx opens with device password" \
        bash -c "DPW=\"\$1\" '$O' pkcs12 -in '$DEP/webserver_cert.pfx' -passin env:DPW -noout" _ "$dpw"
    check_not "[B] deploy: webserver_cert.pfx rejects a wrong password" \
        "$O" pkcs12 -in "$DEP/webserver_cert.pfx" -passin pass:definitely-wrong -noout
    check "[B] deploy: pfx contains the leaf cert" nonempty_eq \
        "$(DPW="$dpw" "$O" pkcs12 -in "$DEP/webserver_cert.pfx" -passin env:DPW -nokeys -clcerts 2>/dev/null | "$O" x509 -noout -fingerprint 2>/dev/null)" \
        "$("$O" x509 -noout -fingerprint -in "$L")"
    check "[B] deploy: pfx contains the private key" \
        bash -c "DPW=\"\$1\" '$O' pkcs12 -in '$DEP/webserver_cert.pfx' -passin env:DPW -nocerts -nodes 2>/dev/null | grep -q 'PRIVATE KEY'" _ "$dpw"

    if [ "${COSU_TEST_KEEP:-0}" = "1" ]; then echo "  (kept scratch dir: $WORK)"; else rm -rf "$WORK"; fi
}

# ---------- static check across the shipped scripts ----------
echo "=== Static check ==="
if grep -nE 'pass(in|out)?[[:space:]]+pass:' "$REPO"/*.sh > /tmp/cosu_static_$$ 2>/dev/null; then
    bad "[A] no shipped script passes a password with 'pass:'  ($(wc -l < /tmp/cosu_static_$$) occurrences)"
    # file:line: of each offender (the matched text itself is just code, not a secret)
    sed -E 's#^([^:]+):([0-9]+):.*#        | \1:\2#' /tmp/cosu_static_$$ | sed 's#/[^|]*/#/#'
else
    ok "[A] no shipped script passes a password with 'pass:'"
fi
rm -f /tmp/cosu_static_$$

# Plain password with no special characters, then a hostile one per tier.
run_scenario "plain passwords"   "RootPass-S3cret" "SignerPass-S3cret" "DevicePass-S3cret"
run_scenario "hostile passwords" $'ro ot$1\'x"*;R' $'sig ner$2\'y"*;S' $'dev ice$3\'z"*;D'

echo
echo "=============================="
echo "Passed: $PASSES   Failed: $FAILS"
if [ "$FAILS" -gt 0 ]; then
    printf 'Failed checks:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
exit 0
