# 🧠 Zabbix 7.0 + Grafana 12 no Proxmox 9 (Ubuntu 24.04) — Guia passo a passo

**Autor:** JonathaN — Analista de Infraestrutura  
**Última revisão:** 2025-10  
**Objetivo:** monitoramento com **Zabbix (coleta)** e **Grafana (dashboards)** dentro do **Proxmox VE 9**.

---

## 🗺️ Visão geral do ambiente

- **Hypervisor:** Proxmox VE 9.0.3  
- **VM Zabbix/Grafana:** Ubuntu Server 24.04.3 LTS, 2 vCPU, 4 GB RAM, 30 GB disco, rede `virtio` (vmbr0)  
- **Teclado/Idioma:** **Português (Brasil) — ABNT2**  
- **IP de exemplo:** `172.24.4.138`

---

## 📦 1) Baixar ISO do Ubuntu no Proxmox


No host Proxmox (Shell):

```bash
mkdir -p /var/lib/vz/template/iso
cd /var/lib/vz/template/iso
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
```

![img1](https://github.com/user-attachments/assets/f1a21184-7d3a-4c12-9c92-5bc996bf2026)


> **Dica:** se um link 24.04.X retornar 404, pegue o **X mais recente** em `releases.ubuntu.com/24.04/`.

---

## 🖥️ 2) Criar a VM no Proxmox

- **Nome:** `zabbix-server`  
- **SO:** Ubuntu 24.04 (usar ISO baixada)  
- **BIOS:** OVMF (UEFI) ou SeaBIOS  
- **SCSI Controller:** VirtIO SCSI  
- **Disco:** 30 GB (local-lvm), `iothread=on`  
- **CPU:** `sockets=1`, `cores=2`  
- **Memória:** 4096 MB  
- **Rede:** `virtio, bridge=vmbr0`  

> **Se aparecer** `TASK ERROR: KVM virtualization configured, but not available`  
> ➜ Ative **Intel VT-x/AMD-V/SVM** na BIOS do host (ou habilite nested virtualization se o Proxmox estiver dentro de outro hypervisor).

![anigif](https://github.com/user-attachments/assets/ad361fde-fb75-460c-8f7c-70ced52bdb20)


---

## ⌨️ 3) Instalar o Ubuntu (pt-BR + ABNT2)

No instalador:
- **Idioma:** Português (Brasil)  
- **Layout de teclado:** **Português (Brazil, ABNT2)**  
- **Tipo:** “Ubuntu Server” (não use o “minimized”)  
- **Instale o OpenSSH Server**  
- **Hostname:** `zabbix-server`

> **Teclado bagunçado?** Volte uma tela e selecione **Português (Brazil, ABNT2)**.  
> **NoVNC do Proxmox:** ajuste o ícone de teclado para **pt-br**.

> **Ao finalizar instalação:** se aparecer  
> `Please remove the installation medium, then press ENTER`  
> ➜ em **Hardware → CD/DVD** selecione **No media**, volte ao console e **ENTER**.

![gifubuntu](https://github.com/user-attachments/assets/8bc0e6a5-3357-4448-af37-c9aabe60ecdc)

# 🧩 Erro: Failed unmounting cdrom.mount — /cdrom (Proxmox)

**Contexto:**  
Durante a instalação de uma VM (ex: Ubuntu ou Debian) no **Proxmox**, pode aparecer o erro:

![erro1](https://github.com/user-attachments/assets/5e9459c2-20cf-48df-8a27-9deb89d96706)

### 🩵 Método 1 — A mais simples (recomendada)

1. **Quando aparecer essa tela**, apenas **pressione `ENTER`**.  
2. Aguarde o sistema **finalizar a instalação e reiniciar** a VM.  
3. No **Proxmox**, vá até a VM → **Aba “Hardware”**.  
4. Selecione o **CD/DVD Drive (geralmente `ide2`)**.  
   - Clique em **“Remove”**  
   - ou em **“Edit” → “Do not use any media”**.  
5. **Inicie a VM novamente.**

> Isso evita que o sistema tente inicializar pela ISO após a instalação.

![erro2](https://github.com/user-attachments/assets/c57ef6ba-f476-42ef-a847-babd4ea9fd1d)

---

## 🔑 4) Acessar por SSH e atualizar

![ip](https://github.com/user-attachments/assets/9465283f-ffbf-4637-b1ed-7c596c656caf)

### 🌐 Descobrir o IP da VM

Dentro do console da VM no **Proxmox**, execute:

```bash
ip a

No Windows (PowerShell):

```powershell
ssh jonathan@172.24.4.138
# primeira vez: responda yes; depois digite a senha
```

Dentro da VM:

```bash
sudo -i
apt update && apt upgrade -y
```

> **Colar no PowerShell:** `Ctrl+Shift+V` ou botão direito.  
> Melhor ainda: use o **Windows Terminal** (aceita `Ctrl+V`).

---

## 🐬 5) Instalar Zabbix 7.0 + MariaDB + Agent + Frontend

```bash
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
dpkg -i zabbix-release_7.0-2+ubuntu24.04_all.deb
apt update
apt install -y zabbix-server-mysql zabbix-frontend-php php8.3-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-agent mariadb-server
systemctl enable --now mariadb
```

**Endurecer o MariaDB (laboratório):**
```bash
mysql_secure_installation
# Enter (vazio) / n / y (senha root) / y / y / y / y
# senha usada no lab: 1234567
```

**Criar DB e usuário do Zabbix:**
```bash
mysql -uroot -p1234567 <<'SQL'
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER zabbix@localhost IDENTIFIED BY '1234567';
GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;
FLUSH PRIVILEGES;
SQL
```

**Importar schema:**
```bash
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -p1234567 zabbix
```

**Configurar Zabbix + timezone PHP:**
```bash
sed -i 's/^#\?DBPassword=.*/DBPassword=1234567/' /etc/zabbix/zabbix_server.conf
sed -i 's@;date.timezone =@date.timezone = America/Sao_Paulo@' /etc/php/*/apache2/php.ini
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2
```

---

## 🌐 6) Primeiro acesso ao Zabbix

![anigifff](https://github.com/user-attachments/assets/30958529-31bc-408a-bdf7-3b21e1346386)

Abra `http://SEU_IP/zabbix`
http://172.24.4.138/ - Zabbix
Login padrão:
```
Usuário: Admin     (A maiúsculo!)
Senha:   zabbix
```

**Idioma PT-BR sumiu?**  
```bash
locale -a | grep pt_BR || locale-gen pt_BR.UTF-8
systemctl restart apache2
```
Depois em **Perfil → Língua → Português (pt_BR)**.

---

## 📊 7) Instalar Grafana 12 e habilitar plugin Zabbix (via CLI)

```bash
wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
apt update
apt install -y grafana
systemctl enable --now grafana-server
```

**Instalar plugin do Zabbix (JavaScript) pela CLI:**
```bash
grafana-cli plugins install alexanderzobnin-zabbix-app
```



**Habilitar carregamento do plugin (editar `grafana.ini`):**
```bash
nano /etc/grafana/grafana.ini
# adicione/edite:
[plugins]
allow_loading_unsigned_plugins = alexanderzobnin-zabbix-app
# salvar: Ctrl+O, Enter. Sair: Ctrl+X
systemctl restart grafana-server
```
![cats](https://github.com/user-attachments/assets/649d0b38-10f0-4409-a48f-3fa198d25454)


> 🔧 **Erros que enfrentei e solução**
> - *“Failed to install plugin” na UI*: instalar pela **CLI** e permitir em `[plugins]`.  
> - *Plugin “already installed”*: reinicie o serviço e adicione a data source.  
> - *Não consigo colar no PowerShell*: use **Ctrl+Shift+V** ou Windows Terminal.

---

## 🔗 8) Conectar Grafana → Zabbix (Data Source)

Acesse `http://SEU_IP:3000` (admin/admin) e altere a senha.

**Menu → Connections → Data sources → Add data source → Zabbix**

**URL da API do Zabbix:**
```
http://SEU_IP/zabbix/api_jsonrpc.php
http://172.24.4.138:3000/ - Grafana
http://172.24.4.138/ - Zabbix
```
![dwadwa](https://github.com/user-attachments/assets/176ab495-a36e-4028-aad9-a597efc4f118)

**Authentication (TLS settings):**  
**NÃO marque nada**:
- ☐ Add self-signed certificate  
- ☐ TLS Client Authentication  
- ☐ Skip TLS certificate validation

**Zabbix Connection**
- **Auth type:** User and password  
- **Username:** `Admin`  
- **Password:** `zabbix`  
> ⚠️ O “A” de **Admin** é **maiúsculo** (sensível a caso).

**Zabbix API**
- **Cache TTL:** `1h`  
- **Timeout:** `30`

**Trends**
- ✅ **Enable Trends** (melhora performance)

**Finalize:** **Save & Test**  
Deve aparecer:  
`Zabbix API version: 7.0.x — Connection successful`.

![anigifffeaw](https://github.com/user-attachments/assets/3240a99d-ed43-4751-a12a-29a14d0218f2)

---

## 🧰 9) Dicas úteis de operação

- Ver serviços:
  ```bash
  systemctl status zabbix-server zabbix-agent apache2 grafana-server
  ```
- Logs:
  ```bash
  journalctl -u zabbix-server -f
  journalctl -u grafana-server -f
  ```
- Usuário/credencial do banco:
  ```bash
  mysql -uzabbix -p1234567 zabbix
  ```

---

## 🛑 Problemas comuns (e como resolvi)

- **KVM não disponível ao iniciar VM**  
  ➜ Habilitar **VT-x/AMD-V** na BIOS do host / nested virtualization.

- **Erro ao desmontar `/cdrom`**  
  ➜ Em **Hardware → CD/DVD → No media** e pressione **ENTER**.

- **Teclado “doido” (acentos/ç errados)**  
  ➜ Configure **Português (Brazil, ABNT2)** no instalador e console.

- **SSH “Connection refused”**  
  ➜ `apt install -y openssh-server && systemctl enable --now ssh`.

- **Login Zabbix falhou**  
  ➜ Usuário é **Admin** (A maiúsculo). Senha padrão `zabbix`.

- **PT-BR não aparece no Zabbix**  
  ➜ `locale-gen pt_BR.UTF-8 && systemctl restart apache2`.

- **Plugin do Zabbix falhou na UI**  
  ➜ Instale pela **CLI** e permita no `grafana.ini`.

---

## ✅ Resultado final


![gifgraficos](https://github.com/user-attachments/assets/178a5904-4664-42ab-b13e-244bbffe526e)


- **Zabbix** rodando
- **Grafana** rodando para criação de graficos
- Ambiente documentado para **equipe de Infra** e **auditoria**


