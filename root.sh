#!/bin/bash
#
# 功能：
#  1. 同时修改 /etc/ssh/sshd_config 及 /etc/ssh/sshd_config.d/*.conf：
#     - 将 PasswordAuthentication 改为 yes
#     - 将 PermitRootLogin 改为 yes
#     - 如果存在 AllowUsers 且不包含 root，则删除该行
#  2. 处理 /root/.ssh/authorized_keys，只保留从 ssh-rsa 开始的公钥行
#     (删除行首到 ssh-rsa 之间的文字；不含 ssh-rsa 的行直接删除)
#  3. 提示两次输入新的 root 密码并匹配，验证成功后更新
#  4. 重启 SSH 服务
#

#--- 必须使用 root 身份执行 ---
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户权限运行此脚本。"
  exit 1
fi

# 要处理的 SSH 配置文件列表（包括主配置文件和 .d 目录下的所有 .conf）
SSH_CONFIG_FILES=("/etc/ssh/sshd_config")

# 如果 /etc/ssh/sshd_config.d 目录存在且里面有 .conf 文件，则添加到列表
if [ -d "/etc/ssh/sshd_config.d" ]; then
  for conf in /etc/ssh/sshd_config.d/*.conf; do
    if [ -f "$conf" ]; then
      SSH_CONFIG_FILES+=("$conf")
    fi
  done
fi

echo "即将修改以下 SSH 配置文件："
printf '%s\n' "${SSH_CONFIG_FILES[@]}"
echo

#--- 1) 修改所有配置文件 ---
for config_file in "${SSH_CONFIG_FILES[@]}"; do
  echo "正在处理文件: $config_file"

  # (a) 强制将 PasswordAuthentication 改为 yes
  sed -i 's/^[#[:space:]]*\(PasswordAuthentication\)[[:space:]]\(no\|yes\)/\1 yes/' "$config_file"

  # (b) 强制将 PermitRootLogin 改为 yes
  sed -i 's/^[#[:space:]]*\(PermitRootLogin\)[[:space:]]\(no\|prohibit-password\|forced-commands-only\|yes\)/\1 yes/' "$config_file"

  # (c) 如果存在 AllowUsers 且不包含 root，则删除该行
  if grep -Eq '^AllowUsers' "$config_file"; then
    if ! grep -Eq '^AllowUsers.*\broot\b' "$config_file"; then
      echo "  - 检测到 AllowUsers 配置且不包含 root，将删除该行..."
      sed -i '/^AllowUsers/d' "$config_file"
    else
      echo "  - AllowUsers 中已包含 root，跳过删除。"
    fi
  fi

  echo "已处理文件: $config_file"
  echo
done

#--- 2) 处理 /root/.ssh/authorized_keys ---
AUTH_KEYS="/root/.ssh/authorized_keys"
if [ -f "$AUTH_KEYS" ]; then
  echo "正在处理 $AUTH_KEYS 中的公钥条目..."
  # 说明：
  #   /ssh-rsa/!d  -> 如果本行不包含 ssh-rsa，则删除此行
  #   s/.*\(ssh-rsa.*\)/\1/  -> 将从行首到 ssh-rsa 之间的所有文本删除，仅保留 ssh-rsa 开始到行尾
  sed -i '/ssh-rsa/!d; s/.*\(ssh-rsa.*\)/\1/' "$AUTH_KEYS"
  echo "已完成对 $AUTH_KEYS 的处理。"
else
  echo "未发现 $AUTH_KEYS 文件，跳过处理。"
fi
echo

#--- 3) 重启 SSH 服务 ---
echo "重启 SSH 服务以使新配置生效..."
if command -v systemctl &>/dev/null; then
  systemctl restart ssh
else
  service ssh restart
fi
echo "SSH 配置已更新。"
echo

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

echo
echo "脚本执行完成。"
