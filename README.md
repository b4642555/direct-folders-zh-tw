# Direct Folders 繁體中文翻譯

適用於 **Direct Folders 4.3.5 的設定視窗**，使用臺灣常見用語。

[下載安裝包](https://github.com/b4642555/direct-folders-zh-tw/releases/latest/download/direct-folders-zh-tw.zip) · [原廠網站](https://codesector.com/directfolders)

## 安裝

1. 先從原廠安裝 Direct Folders 4.3.5。
2. 下載上方安裝包，**解壓縮整個資料夾**。請先關閉 Direct Folders 的設定視窗。
3. 雙擊 **`Install.cmd`**。若 Windows 顯示管理員授權視窗，選擇「是」。

完成後會開啟繁體中文設定視窗。使用 Windows 內建 PowerShell，不需要安裝 Python、Node.js 或其他套件。

也可以使用 GitHub 的 **Code → Download ZIP** 下載。請先解壓縮，保留 `Install.ps1`、`tools`、`translations` 等檔案的相對位置。

### 安裝在其他位置

若程式裝在其他磁碟或使用可攜版，開啟 PowerShell，切換至翻譯包資料夾後執行：

```powershell
.\Install.cmd -ProgramDirectory "D:\Apps\Direct Folders"
```

請填入包含 `config.exe` 的資料夾。本工具只接受已驗證的 4.3.5 檔案；版本不符時會停止。

## 翻譯範圍

- 整理我的最愛、選項、文字片段、應用程式等設定分頁。
- 按鈕、下拉選項、滑鼠提示與常用確認訊息。
- 共替換 320 處文字。

**主程式的快捷選單和自動更新程式尚未翻譯。** 使用者自訂的資料夾名稱、路徑、我的最愛、滑鼠與快捷鍵設定都會保留。

本專案只有翻譯字典、版本資訊、套用工具與文件，沒有附上 Direct Folders 原廠 EXE、DLL、安裝程式、任何使用者設定或備份。

## 還原英文

先關閉 Direct Folders 的設定視窗，再雙擊 **`Restore.cmd`**。

安裝時會將原版 `config.exe` 保存到程式資料夾內的 `.direct-folders-zh-tw-backup`，並記錄 SHA256。還原會核對目前程式與原檔備份，確認符合紀錄後恢復原檔。請保留這個備份資料夾。

如果 Direct Folders 已更新，工具會停止，避免將新版覆寫為舊版。此時可重新安裝原廠版本；請等待相容的翻譯包。

## 相容性與限制

- 已驗證原廠安裝版與可攜版的兩份 4.3.5 `config.exe`。檔案 SHA256 清單在 `translations/manifest-4.3.5.json`。
- 安裝工具使用 Windows PowerShell 5.1，已在 Windows 上測試產生翻譯、重複安裝、完整還原及版本拒絕流程。
- 繁中輸出與曾實際開啟確認四個設定分頁的版本一致。可攜版已驗證產生、安裝及還原，尚未逐頁確認其介面。
- 翻譯會修改本機 `config.exe` 的文字資源，修改後原廠數位簽章不再有效。部分 Windows 安全原則可能拒絕開啟修改版；遇到阻擋時，請執行還原或重新安裝原版，保留原有的安全防護設定。
- 原廠更新可能覆蓋翻譯。
- `Install.cmd` 的 PowerShell 執行原則選項只用於這次安裝程序，不會永久更改電腦的執行原則。

## 中鍵沒有反應

在「選項 → 啟動方式」確認中鍵選項是「按滑鼠中鍵」。若選到「Ctrl + 滑鼠中鍵」，需要同時按住 Ctrl 才會觸發。

中鍵適用於檔案對話框及支援的檔案總管。[原廠使用說明](https://support.codesector.com/en/articles/10157893-how-to-use-direct-folders)列有各種觸發方式。翻譯工具本身不會更改中鍵設定。

## 維護與測試

修改用語可編輯 `translations/zh-TW.json`。表單位置資訊與版本限制在 `translations/manifest-4.3.5.json`。若修改後的文字超過固定長度欄位，工具會停止，避免覆寫相鄰資料。

測試需要自己準備原廠英文 `config.exe`，專案不提供該檔案：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Patch.ps1 -OriginalPath "D:\Original\config.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Install.ps1 -OriginalPath "D:\Original\config.exe"
```

測試會在系統暫存資料夾工作，不會修改目前安裝的 Direct Folders。

## 授權與聲明

這是社群製作的非官方翻譯，與 Code Sector 沒有隸屬關係。Direct Folders 與原廠程式的權利屬於各自權利人。

本專案自行撰寫的工具及繁中翻譯採 MIT 授權。保留的原文是用於匹配原廠介面；MIT 授權不涵蓋原廠程式或商標。
