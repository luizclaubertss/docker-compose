#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Cria o usuário 'aluno' caso ainda não exista
# ---------------------------------------------------------------------------
if ! id aluno >/dev/null 2>&1; then
    groupadd --gid 1020 aluno
    useradd \
        --shell /bin/bash \
        --uid 1020 \
        --gid 1020 \
        --groups sudo \
        --password "$(openssl passwd -6 rnpesr)" \
        --create-home \
        --home-dir /home/aluno \
        aluno
fi

# ---------------------------------------------------------------------------
# 2. Garante que o diretório de runtime do sshd existe
# ---------------------------------------------------------------------------
mkdir -p /var/run/sshd
chmod 755 /var/run/sshd

# ---------------------------------------------------------------------------
# 3. Inicia o OpenLDAP (slapd) de forma limpa
#    - mata qualquer processo residual antes de subir
#    - remove socket ldapi residual
#    - sobe diretamente via binário (sem service) para controle total
# ---------------------------------------------------------------------------
LDAP_BASE="dc=example,dc=com"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE}"
LDAP_ADMIN_PW="rnpesr"
LDAP_DATA_DIR="/var/lib/ldap"
LDAP_CONFIG_DIR="/etc/ldap/slapd.d"
LDAP_SOCKET="/var/run/slapd/ldapi"

echo "[entrypoint] Preparando slapd..."
pkill -9 slapd 2>/dev/null || true
sleep 1
rm -f "${LDAP_SOCKET}"
mkdir -p /var/run/slapd
chown openldap:openldap /var/run/slapd

# ---------------------------------------------------------------------------
# 4. Provisionamento na primeira execução
#    Indicador: arquivo /etc/ldap/.provisioned
# ---------------------------------------------------------------------------
if [ ! -f /etc/ldap/.provisioned ]; then
    echo "[entrypoint] Primeira execução — configurando LDAP..."

    # Limpa banco antigo (evita conflito de suffix dc=nodomain)
    rm -f "${LDAP_DATA_DIR}"/*.mdb "${LDAP_DATA_DIR}"/*.lck 2>/dev/null || true

    # Configura olcSuffix, olcRootDN e olcRootPW diretamente nos arquivos
    # de configuração (slapd parado — sem necessidade de dpkg-reconfigure)
    ADMIN_HASH=$(slappasswd -s "${LDAP_ADMIN_PW}")
    MDB_FILE="${LDAP_CONFIG_DIR}/cn=config/olcDatabase={1}mdb.ldif"

    if [ -f "${MDB_FILE}" ]; then
        sed -i "s|^olcSuffix:.*|olcSuffix: ${LDAP_BASE}|" "${MDB_FILE}"
        sed -i "s|^olcRootDN:.*|olcRootDN: ${LDAP_ADMIN_DN}|" "${MDB_FILE}"
        # Remove linha olcRootPW antiga (se existir) e adiciona a nova
        sed -i '/^olcRootPW/d' "${MDB_FILE}"
        echo "olcRootPW: ${ADMIN_HASH}" >> "${MDB_FILE}"
        # Remove CRC32 antigo — slapd regenera automaticamente na leitura
        sed -i '/^# CRC32/d' "${MDB_FILE}"
    fi

    # Cria entrada raiz no banco MDB via slapadd (slapd ainda parado)
    chown -R openldap:openldap "${LDAP_DATA_DIR}"
    slapadd -F "${LDAP_CONFIG_DIR}" -l /dev/stdin <<LDIF
dn: ${LDAP_BASE}
objectClass: top
objectClass: dcObject
objectClass: organization
o: Example
dc: example
LDIF
    chown -R openldap:openldap "${LDAP_DATA_DIR}"

    echo "[entrypoint] Banco MDB inicializado."
fi

# ---------------------------------------------------------------------------
# 5. Sobe o slapd em background
# ---------------------------------------------------------------------------
echo "[entrypoint] Iniciando slapd..."
/usr/sbin/slapd \
    -h "ldap:/// ldapi:///" \
    -u openldap \
    -g openldap \
    -F "${LDAP_CONFIG_DIR}" 2>/dev/null &

# Aguarda o slapd estar pronto (testa até 10 vezes)
RETRIES=10
until ldapsearch -x -H ldap://localhost \
        -D "${LDAP_ADMIN_DN}" \
        -w "${LDAP_ADMIN_PW}" \
        -b "${LDAP_BASE}" \
        "(objectClass=*)" dn >/dev/null 2>&1; do
    RETRIES=$((RETRIES - 1))
    if [ "${RETRIES}" -eq 0 ]; then
        echo "[entrypoint] ERRO: slapd não respondeu após 10 tentativas." >&2
        break
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# 6. Adiciona OU e usuário Charlie na primeira execução
# ---------------------------------------------------------------------------
if [ ! -f /etc/ldap/.provisioned ]; then
    echo "[entrypoint] Adicionando ou=users e usuário Charlie..."
    CHARLIE_HASH=$(slappasswd -s "passwd")

    ldapadd -x -H ldap://localhost \
        -D "${LDAP_ADMIN_DN}" \
        -w "${LDAP_ADMIN_PW}" <<LDIF || true
dn: ou=users,${LDAP_BASE}
objectClass: organizationalUnit
ou: users

dn: cn=charlie,ou=users,${LDAP_BASE}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: charlie
sn: Charlie
givenName: Charlie
uid: charlie
uidNumber: 2001
gidNumber: 2001
homeDirectory: /home/charlie
loginShell: /bin/bash
userPassword: ${CHARLIE_HASH}
mail: charlie@example.com
LDIF

    touch /etc/ldap/.provisioned
    echo "[entrypoint] Usuário Charlie criado com sucesso."
fi

# ---------------------------------------------------------------------------
# 7. SSH em primeiro plano — processo principal do container
#    Se o sshd terminar, o container reinicia automaticamente
#    (requer --restart=always ou restart: always no compose)
# ---------------------------------------------------------------------------
if [ -z "${1:-}" ]; then
    echo "[entrypoint] Iniciando sshd em foreground..."
    exec /usr/sbin/sshd -D
else
    /usr/sbin/sshd -D &
    exec "$@"
fi
