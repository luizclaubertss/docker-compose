#!/usr/bin/env bash
# =============================================
# entrypoint.sh - SSH + OpenLDAP
# Mantenedor: Luiz Claubert <luizclaubertss@gmail.com>
# =============================================

set -e

# ==================== SSH ====================
echo "Iniciando SSH Daemon..."
rm -f /var/run/sshd.pid
mkdir -p /var/run/sshd

# Cria usuário aluno (caso não exista)
if ! id aluno >/dev/null 2>&1; then
    echo "Criando usuário aluno..."
    groupadd --gid 1020 aluno 2>/dev/null || true
    useradd --shell /bin/bash --uid 1020 --gid 1020 --groups sudo \
            --password "$(openssl passwd -1 rnpesr)" --create-home aluno
fi

# ==================== OpenLDAP ====================
echo "Inicializando OpenLDAP (slapd)..."

if ! pgrep slapd > /dev/null; then
    service slapd start
else
    echo "slapd já está em execução."
fi

echo "Aguardando LDAP inicializar..."
for i in {1..30}; do
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "" -s base dn > /dev/null 2>&1; then
        echo "LDAP pronto!"
        break
    fi
    sleep 1
done

# Criar OU se não existir
if ! ldapsearch -x -H ldapi:/// -b "dc=example,dc=local" "(ou=people)" | grep -q "dn:"; then
    echo "Criando OU people..."
    ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: ou=people,dc=example,dc=local
objectClass: organizationalUnit
ou: people
EOF
fi

# Criar usuário Charlie se não existir
if ! ldapsearch -x -H ldapi:/// -b "dc=example,dc=local" "(uid=charlie)" | grep -q "dn:"; then
    echo "Criando usuário Charlie no LDAP..."
    HASH=$(slappasswd -s passwd)

    ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: uid=charlie,ou=people,dc=example,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: charlie
sn: Charlie
givenName: Charlie
cn: Charlie
displayName: Charlie
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/charlie
userPassword: $HASH
EOF

    echo "Usuário Charlie criado com sucesso"
else
    echo "Usuário Charlie já existe."
fi
