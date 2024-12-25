#!/bin/bash
#
# 功能：
#  1. 修改 /etc/ssh/sshd_config:
#     - 设置 PasswordAuthentication yes
#     - 设置 PermitRootLogin yes
#     - 如果存在 AllowUsers 且不含 root 则删除该行
#  2. 在 /root/.ssh/authorized_keys 中删除 ssh-rsa 之前的所有字符，只保留从 ssh-rsa 开始到行尾
#     不包含 ssh-rsa 的行一并删除
#  3. 提示两次输入新的 root 密码并匹配，验证成功后更新
#  4. 重启 SSH 服务
#

#--- 必须使用 root 身份执行 ---
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户权限运行此脚本。"
  exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
AUTH_KEYS="/root/.ssh/authorized_keys"

echo "正在修改 SSH 配置..."

#--- 1) 修改 sshd_config ---
# (a) 强制将 PasswordAuthentication 改为 yes
sed -i 's/^[#[:space:]]*\(PasswordAuthentication\)[[:space:]]\(no\|yes\)/\1 yes/' "$SSHD_CONFIG"

# (b) 强制将 PermitRootLogin 改为 yes
sed -i 's/^[#[:space:]]*\(PermitRootLogin\)[[:space:]]\(no\|prohibit-password\|forced-commands-only\|yes\)/\1 yes/' "$SSHD_CONFIG"

# (c) 如果存在 AllowUsers 且不包含 root，则删除该行
if grep -Eq '^AllowUsers' "$SSHD_CONFIG"; then
  if ! grep -Eq '^AllowUsers.*\broot\b' "$SSHD_CONFIG"; then
    echo "检测到 AllowUsers 配置且不包含 root，将删除该行..."
    sed -i '/^AllowUsers/d' "$SSHD_CONFIG"
  else
    echo "AllowUsers 中已包含 root，跳过删除。"
  fi
fi

#--- 2) 处理 /root/.ssh/authorized_keys ---
# 如果文件存在，则只保留从 "ssh-rsa" 开始到行尾，其他部分删除
# 不包含 "ssh-rsa" 的行一并删除
if [ -f "$AUTH_KEYS" ]; then
  echo "正在处理 $AUTH_KEYS 中的公钥条目..."
  # 说明：
  #   /ssh-rsa/!d  -> 如果本行不包含 ssh-rsa，则删除此行
  #   s/.*\(ssh-rsa.*\)/\1/  -> 将从行首到 ssh-rsa 之间的所有文本删除，仅保留 ssh-rsa 开始到行尾
  sed -i '/ssh-rsa/!d; s/.*\(ssh-rsa.*\)/\1/' "$AUTH_KEYS"
  echo "已完成对 $AUTH_KEYS 的处理。"
fi

#--- 3) 重启 SSH 服务 ---
echo "重启 SSH 服务以使新配置生效..."
if command -v systemctl &>/dev/null; then
  systemctl restart ssh
else
  service ssh restart
fi
echo "SSH 配置已更新。"

#--- 4) 修改 root 密码（双重验证） ---
while true; do
  read -sp "请输入新的 root 密码: " ROOTPASS1
  echo
  read -sp "请再次输入新的 root 密码: " ROOTPASS2
  echo
  if [ "$ROOTPASS1" = "$ROOTPASS2" ]; then
    echo "两次输入的密码一致，正在更新 root 密码..."
    echo "root:${ROOTPASS1}" | chpasswd
    echo "root 密码已更新。"
    break
  else
    echo "两次密码不一致，请重新输入。"
  fi
done

echo "脚本执行完成。"
