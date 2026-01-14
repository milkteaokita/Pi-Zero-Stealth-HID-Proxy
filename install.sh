#!/bin/bash
set -e

# --- [設定區] 請在此修改參數 ---
# USB 製造商名稱
MANUFACTURER_NAME="123" 
# -----------------------------

# 1. 檢查權限與自動偵測使用者
if [ "$EUID" -ne 0 ]; then
  echo "錯誤: 請使用 sudo 執行此腳本 (例如: sudo bash install.sh)"
  exit 1
fi

# 抓取呼叫 sudo 的原始使用者名稱 (如果是直接 root 登入則為 root)
ACTUAL_USER="${SUDO_USER:-$USER}"
# 抓取該使用者目錄
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo ">>> 當前使用者: $ACTUAL_USER"
echo ">>> 安裝路徑: $USER_HOME"

PROXY_SCRIPT="$USER_HOME/proxy.py"
BOOT_SCRIPT="/usr/local/bin/isticktoit_usb"
SERVICE_FILE="/etc/systemd/system/mxmaster.service"

echo ">>> 1. 建立 proxy.py 腳本..."
cat << 'PYTHON_EOF' > $PROXY_SCRIPT
import evdev
from evdev import InputDevice, ecodes, list_devices
import time
import os
import sys
import errno

# --- Python 內部設定 ---
GESTURE_BTN_CODE = 277   # 手勢按鍵
GESTURE_THRESHOLD = 50   # 手勢靈敏度
HWHEEL_DIRECTION = 1     # 橫向滾輪方向
SENSITIVITY = 1.0        # 滑鼠靈敏度

KBD_OUT = '/dev/hidg0'
MOUSE_OUT = '/dev/hidg1'
# ---------------------

def get_mouse_path():
    try:
        devices = [InputDevice(path) for path in list_devices()]
        for dev in devices:
            if 'MX Master' in dev.name: return dev.path
    except: pass
    return None

def write_report(fd, report):
    try:
        os.write(fd, report)
    except OSError: pass

def send_mouse_report(fd, buttons, x, y, v_wheel, h_wheel):
    x = max(min(int(x), 127), -127)
    y = max(min(int(y), 127), -127)
    v_wheel = max(min(int(v_wheel), 127), -127)
    h_wheel = max(min(int(h_wheel), 127), -127)
    report = bytearray([buttons, x & 0xFF, y & 0xFF, v_wheel & 0xFF, h_wheel & 0xFF])
    write_report(fd, report)

def send_key_combo(fd, modifier, key):
    write_report(fd, bytearray([modifier, 0, 0, 0, 0, 0, 0, 0]))
    time.sleep(0.02)
    write_report(fd, bytearray([modifier, 0, key, 0, 0, 0, 0, 0]))
    time.sleep(0.15)
    write_report(fd, bytearray([0] * 8))
    time.sleep(0.05)

def main_loop():
    print(f"--- 隱形手勢滑鼠服務啟動 ---")
    while True:
        mouse_dev = None
        kbd_fd = None
        mouse_fd = None
        try:
            path = get_mouse_path()
            if not path:
                time.sleep(1)
                continue
            
            print(f">>> 偵測到滑鼠: {path}，連線中...")
            mouse_dev = InputDevice(path)
            mouse_dev.grab()
            
            if not os.path.exists(KBD_OUT) or not os.path.exists(MOUSE_OUT):
                time.sleep(1)
                continue
                
            kbd_fd = os.open(KBD_OUT, os.O_RDWR | os.O_NONBLOCK)
            mouse_fd = os.open(MOUSE_OUT, os.O_RDWR | os.O_NONBLOCK)
            print(">>> 連線成功！")

            gesture_mode = False
            gesture_triggered = False
            accumulated_x = 0
            accumulated_y = 0
            current_buttons = 0
            dx, dy, dv, dh = 0, 0, 0, 0

            for event in mouse_dev.read_loop():
                if event.type == ecodes.EV_KEY:
                    if event.code == GESTURE_BTN_CODE:
                        gesture_mode = (event.value == 1)
                        if gesture_mode:
                            gesture_triggered = False
                            accumulated_x = 0
                            accumulated_y = 0
                        continue
                    
                    mask = 0
                    if event.code == ecodes.BTN_LEFT: mask = 1
                    elif event.code == ecodes.BTN_RIGHT: mask = 2
                    elif event.code == ecodes.BTN_MIDDLE: mask = 4
                    elif event.code == ecodes.BTN_SIDE: mask = 8
                    elif event.code == ecodes.BTN_EXTRA: mask = 16
                    
                    if mask > 0:
                        if event.value == 1: current_buttons |= mask
                        else: current_buttons &= ~mask
                        send_mouse_report(mouse_fd, current_buttons, 0, 0, 0, 0)

                elif event.type == ecodes.EV_REL:
                    if gesture_mode:
                        if gesture_triggered: continue
                        if event.code == ecodes.REL_X:
                            accumulated_x += event.value
                            if accumulated_x < -GESTURE_THRESHOLD:
                                print("Gesture: Win+Ctrl+Left (桌面左移)")
                                send_key_combo(kbd_fd, 0x09, 0x50)
                                gesture_triggered = True
                            elif accumulated_x > GESTURE_THRESHOLD:
                                print("Gesture: Win+Ctrl+Right (桌面右移)")
                                send_key_combo(kbd_fd, 0x09, 0x4F)
                                gesture_triggered = True
                        elif event.code == ecodes.REL_Y:
                            accumulated_y += event.value
                            if accumulated_y < -GESTURE_THRESHOLD: 
                                print("Gesture: Win+Tab (多工)")
                                send_key_combo(kbd_fd, 0x08, 0x2B) 
                                gesture_triggered = True
                            elif accumulated_y > GESTURE_THRESHOLD: 
                                print("Gesture: Win+D (顯示桌面)")
                                send_key_combo(kbd_fd, 0x08, 0x07)
                                gesture_triggered = True
                        continue
                    
                    if event.code == ecodes.REL_X: dx += event.value
                    elif event.code == ecodes.REL_Y: dy += event.value
                    elif event.code == ecodes.REL_WHEEL: dv += event.value
                    elif event.code == ecodes.REL_HWHEEL: dh += (event.value * HWHEEL_DIRECTION)

                elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
                    if gesture_mode: continue
                    if dx != 0 or dy != 0 or dv != 0 or dh != 0:
                        send_mouse_report(mouse_fd, current_buttons, int(dx * SENSITIVITY), int(dy * SENSITIVITY), dv, dh)
                        dx, dy, dv, dh = 0, 0, 0, 0

        except OSError as e:
            if e.errno == errno.ENODEV: print("!!! 滑鼠斷線/睡眠 !!!")
        except Exception: time.sleep(1)
        finally:
            try:
                if mouse_dev: mouse_dev.close()
                if kbd_fd: os.close(kbd_fd)
                if mouse_fd: os.close(mouse_fd)
            except: pass
            time.sleep(1)

if __name__ == "__main__":
    main_loop()
PYTHON_EOF

chown $ACTUAL_USER:$ACTUAL_USER $PROXY_SCRIPT
chmod +x $PROXY_SCRIPT

echo ">>> 2. 建立 USB Gadget 啟動腳本 ..."
python3 -c "
import os

script_content = r'''#!/bin/bash
set -e
# 清理舊設定
if [ -d /sys/kernel/config/usb_gadget/isticktoit ]; then
    echo '' > /sys/kernel/config/usb_gadget/isticktoit/UDC 2>/dev/null || true
    sleep 0.2
fi
rm -rf /sys/kernel/config/usb_gadget/isticktoit 2>/dev/null || true

# 建立 Gadget
mkdir -p /sys/kernel/config/usb_gadget/isticktoit
cd /sys/kernel/config/usb_gadget/isticktoit

# 設定 USB ID (模擬 Receiver)
echo 0x046d > idVendor
echo 0xc52b > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo '1234567890ABCDEF' > strings/0x409/serialnumber
echo '$MANUFACTURER_NAME' > strings/0x409/manufacturer
echo 'USB Receiver' > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo 'Default' > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

# 建立鍵盤功能 (HID)
mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol
echo 1 > functions/hid.usb0/subclass
echo 8 > functions/hid.usb0/report_length
python3 -c \"
with open('functions/hid.usb0/report_desc', 'wb') as f:
    f.write(b'\\x05\\x01\\x09\\x06\\xa1\\x01\\x05\\x07\\x19\\xe0\\x29\\xe7\\x15\\x00\\x25\\x01\\x75\\x01\\x95\\x08\\x81\\x02\\x95\\x01\\x75\\x08\\x81\\x03\\x95\\x05\\x75\\x01\\x05\\x08\\x19\\x01\\x29\\x05\\x91\\x02\\x95\\x01\\x75\\x03\\x91\\x03\\x95\\x06\\x75\\x08\\x15\\x00\\x25\\x65\\x05\\x07\\x19\\x00\\x29\\x65\\x81\\x00\\xc0')
\"

# 建立滑鼠功能 (HID)
mkdir -p functions/hid.usb1
echo 2 > functions/hid.usb1/protocol
echo 1 > functions/hid.usb1/subclass
echo 5 > functions/hid.usb1/report_length 
python3 -c \"
with open('functions/hid.usb1/report_desc', 'wb') as f:
    f.write(b'\\x05\\x01\\x09\\x02\\xa1\\x01\\x09\\x01\\xa1\\x00\\x05\\x09\\x19\\x01\\x29\\x05\\x15\\x00\\x25\\x01\\x95\\x05\\x75\\x01\\x81\\x02\\x95\\x01\\x75\\x03\\x81\\x03\\x05\\x01\\x09\\x30\\x09\\x31\\x09\\x38\\x15\\x81\\x25\\x7f\\x75\\x08\\x95\\x03\\x81\\x06\\x05\\x0c\\x0a\\x38\\x02\\x15\\x81\\x25\\x7f\\x75\\x08\\x95\\x01\\x81\\x06\\xc0\\xc0')
\"

# 綁定功能並啟動
ln -s functions/hid.usb0 configs/c.1/
ln -s functions/hid.usb1 configs/c.1/
ls /sys/class/udc > UDC
'''

# 寫入 USB 腳本
with open('/usr/local/bin/isticktoit_usb', 'w') as f:
    f.write(script_content)
"
chmod +x $BOOT_SCRIPT

echo ">>> 3. 設定 Systemd 服務..."
cat << SERVICE_EOF > $SERVICE_FILE
[Unit]
Description=Stealth Proxy Service
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/isticktoit_usb
ExecStart=/usr/bin/python3 $PROXY_SCRIPT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo ">>> 4. 啟用服務..."
systemctl daemon-reload
systemctl enable mxmaster.service
systemctl restart mxmaster.service

echo ">>> 安裝完成！"
echo ">>> Python 腳本位置: $PROXY_SCRIPT"
echo ">>> 如果需要修改按鍵定義，請直接編輯該檔案。"
