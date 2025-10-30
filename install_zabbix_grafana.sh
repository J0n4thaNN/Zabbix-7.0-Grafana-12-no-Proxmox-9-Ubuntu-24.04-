#!/usr/bin/env bash
set -euo pipefail

# ================================
# Zabbix 7.0 + Grafana 12 (Ubuntu 24.04)
# Autor: Jonathan (Infra)
# Testado em: Ubuntu Server 24.04.3 LTS (em VM Proxmox 9)
# ================================

### ===== Variáveis (personalize se quiser) =====
ZBX_DB="zabbix"
ZBX_DB_USER="zabbix"
ZBX_DB_PASS="${ZBX_DB_PASS:-1234567}"
TZ_ZONE="${TZ_ZONE:-America/Sao_Paulo}"
GRAFANA_PLUGIN="alexanderzobnin-zabbix-app"
ZBX_RELEASE_DEB="zabbix-release_7.0-2+ubuntu24.04_all.deb"
ZBX_RELEASE_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/${ZBX_RELEASE_DEB}"
GRAFANA_KEYRING="/usr/share/keyrings/grafana.gpg"
GRAFANA_LIST="/etc/apt/sources.list.d/grafana.list"

log() { echo -e "\e[1;32m[OK]\e[0m $*"; }
info() { echo -e "\e[1;34m[i]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err() { echo -e "\e[1;31m[ERRO]\e[0m $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Execute como root (sudo -i)."
    exit 1
  fi
}

check_ubuntu_2404() {
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
    warn "Sistema detectado: ${PRETTY_NAME}. Script foi escrito para Ubuntu 24.04."
  fi
}

get_ip() {
  IP="$(hostname -I | awk '{print $1}')"
  if [[ -z "${IP}" ]]; then
    IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')"
  fi
  echo "${IP:-SEU_IP}"
}

require_root
check_ubuntu_2404

info "Atualizando pacotes…"
apt update -y
DEBIAN_FRONTEND=noninteractive apt upgrade -y
apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates software-properties-common locales

info "Configurando timezone (${TZ_ZONE}) e locale pt_BR.UTF-8…"
timedatectl set-timezone "${TZ_ZONE}" || true
locale-gen pt_BR.UTF-8 || true

if ! dpkg -s zabbix-server-mysql >/dev/null 2>&1; then
  info "Instalando repositório do Zabbix 7.0…"
  cd /tmp
  wget -q "${ZBX_RELEASE_URL}"
  dpkg -i "${ZBX_RELEASE_DEB}"
  apt update -y

  info "Instalando Zabbix server/frontend/agent + MariaDB + PHP…"
  apt install -y     zabbix-server-mysql zabbix-frontend-php php8.3-mysql zabbix-apache-conf     zabbix-sql-scripts zabbix-agent mariadb-server

  systemctl enable --now mariadb
else
  info "Zabbix já instalado. Pulando reinstalação."
fi

info "Configurando banco de dados do Zabbix…"
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS ${ZBX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZBX_DB_USER}'@'localhost' IDENTIFIED BY '${ZBX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZBX_DB}.* TO '${ZBX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

if ! mysql -u"${ZBX_DB_USER}" -p"${ZBX_DB_PASS}" -e "USE ${ZBX_DB}; SHOW TABLES;" | grep -q "^users$"; then
  info "Importando schema inicial do Zabbix (pode levar alguns minutos)…"
  zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -u"${ZBX_DB_USER}" -p"${ZBX_DB_PASS}" "${ZBX_DB}"
else
  info "Tabelas já existentes no DB ${ZBX_DB}. Pulando import."
fi

info "Ajustando /etc/zabbix/zabbix_server.conf…"
sed -i "s/^#\?DBPassword=.*/DBPassword=${ZBX_DB_PASS}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^#\?DBName=.*/DBName=${ZBX_DB}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^#\?DBUser=.*/DBUser=${ZBX_DB_USER}/" /etc/zabbix/zabbix_server.conf

info "Ajustando timezone no PHP para ${TZ_ZONE}…"
for INI in /etc/php/*/apache2/php.ini; do
  [ -f "$INI" ] || continue
  if grep -q "^;date.timezone" "$INI"; then
    sed -i "s@^;date.timezone =.*@date.timezone = ${TZ_ZONE}@" "$INI"
  elif grep -q "^date.timezone" "$INI"; then
    sed -i "s@^date.timezone =.*@date.timezone = ${TZ_ZONE}@" "$INI"
  else
    echo "date.timezone = ${TZ_ZONE}" >> "$INI"
  fi
done

systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2
log "Zabbix + MariaDB + Apache configurados."

if ! dpkg -s grafana >/dev/null 2>&1; then
  info "Adicionando repositório do Grafana OSS…"
  wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor -o "${GRAFANA_KEYRING}"
  echo "deb [signed-by=${GRAFANA_KEYRING}] https://packages.grafana.com/oss/deb stable main" | tee "${GRAFANA_LIST}" >/dev/null
  apt update -y

  info "Instalando Grafana…"
  apt install -y grafana
  systemctl enable --now grafana-server
else
  info "Grafana já instalado. Pulando reinstalação."
fi

info "Instalando plugin ${GRAFANA_PLUGIN} via CLI…"
grafana-cli plugins install "${GRAFANA_PLUGIN}" || true

info "Permitindo plugin não assinado no grafana.ini…"
GRAFANA_INI="/etc/grafana/grafana.ini"
if ! grep -q "^\[plugins\]" "${GRAFANA_INI}"; then
  printf "\n[plugins]\n" >> "${GRAFANA_INI}"
fi

if grep -q "^allow_loading_unsigned_plugins" "${GRAFANA_INI}"; then
  sed -i "s/^allow_loading_unsigned_plugins.*/allow_loading_unsigned_plugins = ${GRAFANA_PLUGIN}/" "${GRAFANA_INI}"
else
  sed -i "/^\[plugins\]/a allow_loading_unsigned_plugins = ${GRAFANA_PLUGIN}" "${GRAFANA_INI}"
fi

systemctl restart grafana-server
log "Grafana configurado com plugin do Zabbix."

info "Garantindo locale pt_BR instalado…"
locale -a | grep -q pt_BR || locale-gen pt_BR.UTF-8
systemctl restart apache2

IP="$(get_ip)"

cat <<EOF

===============================================================
✅ Instalação concluída!

Acesse:
- Zabbix:  http://${IP}/zabbix
  * Usuário: Admin  (A maiúsculo)
  * Senha:   zabbix

- Grafana: http://${IP}:3000
  * Usuário: admin
  * Senha:   admin  (altere no primeiro login)
  * Adicione a Data Source "Zabbix" com a URL:
    http://${IP}/zabbix/api_jsonrpc.php
    Auth type: User and password (Admin / zabbix)
    Cache TTL: 1h | Timeout: 30 | Trends: habilitado

Serviços:
  systemctl status zabbix-server zabbix-agent apache2 grafana-server

Banco:
  mysql -u${ZBX_DB_USER} -p${ZBX_DB_PASS} ${ZBX_DB}

Observações:
- Se estiver instalando via console do Proxmox e a ISO permanecer montada,
  remova em: VM -> Hardware -> CD/DVD -> "Do not use any media" e reinicie.

===============================================================
EOF
