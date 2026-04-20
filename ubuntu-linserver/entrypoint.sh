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
echo "Iniciando serviço OpenLDAP (slapd)..."
service slapd start

# Aguarda o LDAP ficar pronto
echo "Aguardando LDAP inicializar..."
for i in {1..30}; do
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "" -s base > /dev/null 2>&1; then
        echo "LDAP pronto!"
        break
    fi
    sleep 1
done

# Cria o usuário Charlie (executa apenas na primeira inicialização)
if ! ldapsearch -x -H ldapi:/// -b "dc=example,dc=local" "(uid=charlie)" > /dev/null 2>&1; then
    echo "Criando usuário Charlie no LDAP..."
    ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: ou=people,dc=example,dc=local
objectClass: organizationalUnit
ou: people

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
userPassword: passwd
EOF
    echo "Usuário Charlie criado com sucesso (senha: passwd)"
else
    echo "Usuário Charlie já existe."
fi

# Mantém o container rodando com SSH em foreground
echo "Iniciando SSH em foreground..."
exec /usr/sbin/sshd -D -e
