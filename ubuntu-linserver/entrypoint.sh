#!/usr/bin/env bash
# =============================================
# entrypoint.sh - Versão simplificada (SSH + LDAP)
# Mantenedor: Luiz Claubert <luizclaubertss@gmail.com>
# =============================================

set -e

# ==================== CRIAÇÃO DO USUÁRIO 'aluno' ====================
if ! id aluno >/dev/null 2>&1; then
    echo "Criando usuário 'aluno'..."
    groupadd --gid 1020 aluno 2>/dev/null || true
    useradd --shell /bin/bash \
            --uid 1020 \
            --gid 1020 \
            --groups sudo \
            --password "$(openssl passwd -1 rnpesr)" \
            --create-home \
            --home-dir /home/aluno \
            aluno
fi

# ==================== CONFIGURAÇÃO SSH (garante que sempre rode) ====================
echo "Iniciando SSH Daemon..."

# Remove possíveis arquivos PID travados (boa prática)
rm -f /var/run/sshd.pid

# Garante que o diretório /var/run/sshd exista
mkdir -p /var/run/sshd

# Inicia o SSHD em foreground (recomendado para Docker)
# O container só sai se o sshd cair → Docker pode reiniciar automaticamente com --restart=unless-stopped
exec /usr/sbin/sshd -D -e
