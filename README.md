# Pi-Zero-Stealth-HID-Proxy
一個可以讓你的MX Master系列滑鼠在公司也能發揮100%功能的小裝置

## 你需要準備以下設備
- Raspberry Pi Zero 2W一台
- micro SD卡一張（8GB以上）
- USB Type Micro-B to USB Type-A線2條
- USB Type-A插頭1個

## 安裝方式

1. **下載專案**：
   ```bash
   git clone [https://github.com/milkteaokita/Pi-Zero-Stealth-HID-Proxy.git](https://github.com/milkteaokita/Pi-Zero-Stealth-HID-Proxy.git)
   cd Pi-Zero-Stealth-HID-Proxy
2. **修改內容**

   git clone 完成後，請自行修改第 6 行的 MANUFACTURER_NAME。
4. **執行安裝**
   ```bash
   sudo bash install.sh
5. **配對滑鼠**
   於 Pi 內執行藍芽配對
   操作步驟：

   ```bash
   sudo bluetoothctl
   ```
   開啟藍牙掃描： 在 [bluetooth]# 提示字元下，輸入：
   ```bash
   power on
   agent on
   default-agent
   scan on
   ```
   讓滑鼠進入配對模式：
   翻到滑鼠底部。

   按下切換按鈕，選擇 1、2、3 其中一個燈號（建議選一個沒用過的，例如 2 號）。
   
   長按 切換按鈕，直到燈號開始快速閃爍。
   
   找到滑鼠並配對：
   
   看終端機畫面，你會看到一堆裝置跳出來。
   
   找到名稱是 MX Master 3S 的裝置，記下它的 MAC 位址（例如 F8:8C:36:XX:XX:XX）。
   
   輸入指令配對與信任：
   
   ```bash
   pair F8:8C:36:XX:XX:XX
   ```
   等待配對成功
   ```bash
   trust F8:8C:36:XX:XX:XX
   connect F8:8C:36:XX:XX:XX
   ```
   (請將 F8:8C... 換成你實際看到的位址)
   
   完成退出： 輸入 exit 離開。



## License & Disclaimer (授權與免責聲明)

This project is licensed under the **CC BY-NC-SA 4.0** (Attribution-NonCommercial-ShareAlike).
**Commercial use of this software is strictly prohibited.**

> **Warning:** This project uses specific Vendor IDs (VID) and Product IDs (PID) for educational and interoperability testing purposes only. The author does not own these IDs. Users are responsible for complying with all applicable laws and workplace policies. The author assumes no liability for misuse.

本專案採用 **CC BY-NC-SA 4.0** 授權。
**嚴禁任何形式的商業用途。**

> **警告：** 本專案使用特定廠商 ID 僅供教育與相容性測試。作者並不擁有這些 ID 的權利。使用者須自行承擔風險並遵守相關法律與公司規範。
