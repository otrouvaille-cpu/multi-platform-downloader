# WebView2 内嵌浏览器登录模块
# 提供 LoginAccount 函数，弹出 WebView2 窗口让用户在平台完成登录
# 自动提取 cookies 并保存为 Netscape 格式

$script:WebView2Available = $false
$script:_WebView2Dir = ""
$script:_WebView2Core = ""
$script:_WebView2WinForms = ""

function Initialize-WebView2 {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolDir
    )

    $script:_WebView2Dir = Join-Path $ToolDir "external\webview2"
    $script:_WebView2Core = Join-Path $script:_WebView2Dir "Microsoft.Web.WebView2.Core.dll"
    $script:_WebView2WinForms = Join-Path $script:_WebView2Dir "Microsoft.Web.WebView2.WinForms.dll"

    if (-not (Test-Path $script:_WebView2Core) -or -not (Test-Path $script:_WebView2WinForms)) {
        return $false
    }

    # 如果已经初始化成功过，直接返回
    if ($script:WebView2Available) { return $true }

    # 预加载原生 WebView2Loader.dll，否则 .NET 找不到
    $loaderDll = Join-Path $ToolDir "WebView2Loader.dll"
    if (-not (Test-Path $loaderDll)) { return $false }

    # 只在第一次加载 native loader
    $nativeLoaderOk = $false
    try { $null = [NativeLoader]; $nativeLoaderOk = $true } catch { }
    if (-not $nativeLoaderOk) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeLoader {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadLibrary(string lpFileName);
}
'@ -ErrorAction Stop
        } catch {
            return $false
        }
    }
    $handle = [NativeLoader]::LoadLibrary($loaderDll)
    if ($handle -eq [IntPtr]::Zero) { return $false }

    # 只在第一次加载 WebView2 程序集
    $wvOk = $false
    try { $null = [Microsoft.Web.WebView2.WinForms.WebView2]; $wvOk = $true } catch { }
    if (-not $wvOk) {
        try {
            Add-Type -Path $script:_WebView2Core -ErrorAction Stop
            Add-Type -Path $script:_WebView2WinForms -ErrorAction Stop
        } catch {
            return $false
        }
    }

    # 只在第一次编译 C# 辅助类
    $helperOk = $false
    try { $null = [WebView2LoginHelper]; $helperOk = $true } catch { }
    if (-not $helperOk) {
        $source = Get-WebView2LoginSource
        try {
            $fwDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
            Add-Type -TypeDefinition $source -ReferencedAssemblies @(
                (Join-Path $fwDir "System.dll"),
                (Join-Path $fwDir "System.Drawing.dll"),
                (Join-Path $fwDir "System.Windows.Forms.dll"),
                $script:_WebView2Core,
                $script:_WebView2WinForms
            ) -ErrorAction Stop
        } catch {
            return $false
        }
    }

    $script:WebView2Available = $true
    return $true
}

function Get-WebView2LoginSource {
    @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

public class WebView2LoginHelper
{
    // ========== 公开类型 ==========

    public class CookieEntry
    {
        public string Domain { get; set; }
        public bool IncludeSubdomains { get; set; }
        public string Path { get; set; }
        public bool Secure { get; set; }
        public long Expiration { get; set; }
        public string Name { get; set; }
        public string Value { get; set; }
    }

    public class LoginResult
    {
        public bool Success { get; set; }
        public bool Cancelled { get; set; }
        public string ErrorMessage { get; set; }
        public string AccountName { get; set; }
        public string AccountId { get; set; }
        public string CookiesNetscape { get; set; }
    }

    // ========== 平台配置 ==========

    private static readonly Dictionary<string, LoginPageConfig> PlatformConfigs;

    static WebView2LoginHelper()
    {
        PlatformConfigs = new Dictionary<string, LoginPageConfig>();
        PlatformConfigs["bilibili"] = new LoginPageConfig {
            Label = "B站", HomeUrl = "https://www.bilibili.com/", LoginUrl = "https://www.bilibili.com/",
            Domains = new[] { "bilibili.com", "biliapi.com", "biliapi.net", "b23.tv" },
            AccountNameCookie = new[] { "DedeUserID" }, AccountIdCookie = new[] { "DedeUserID" },
            UseHashForId = false,
            FetchNameUrl = "https://api.bilibili.com/x/web-interface/nav",
            FetchNameParser = "data.uname"
        };
        PlatformConfigs["douyin"] = new LoginPageConfig {
            Label = "抖音", HomeUrl = "https://www.douyin.com/", LoginUrl = "https://www.douyin.com/",
            Domains = new[] { "douyin.com", "amemv.com", "snssdk.com", "iesdouyin.com" },
            AccountNameCookie = new[] { "uid_tt", "passport_assist_user" },
            AccountIdCookie = new[] { "uid_tt", "uid_tt_ss" }, UseHashForId = false
        };
        PlatformConfigs["twitter"] = new LoginPageConfig {
            Label = "Twitter/X", HomeUrl = "https://x.com/", LoginUrl = "https://x.com/login",
            Domains = new[] { "x.com", "twitter.com" },
            AccountNameCookie = new[] { "twid" }, AccountIdCookie = new[] { "twid" },
            UseHashForId = false,
            IdTransformer = new Func<string, string>(v => v != null && v.StartsWith("u%3D") ? v.Substring(4) : v)
        };
        PlatformConfigs["youtube"] = new LoginPageConfig {
            Label = "YouTube", HomeUrl = "https://www.youtube.com/",
            LoginUrl = "https://accounts.google.com/ServiceLogin?service=youtube&hl=zh-CN",
            Domains = new[] { "youtube.com", "google.com", "accounts.google.com" },
            AccountNameCookie = new[] { "__Secure-1PSID", "SID", "SAPISID" },
            AccountIdCookie = new[] { "__Secure-1PSID", "SID" }, UseHashForId = true
        };
        PlatformConfigs["instagram"] = new LoginPageConfig {
            Label = "Instagram", HomeUrl = "https://www.instagram.com/",
            LoginUrl = "https://www.instagram.com/accounts/login/",
            Domains = new[] { "instagram.com" },
            AccountNameCookie = new[] { "ds_user_id", "sessionid" },
            AccountIdCookie = new[] { "ds_user_id", "sessionid" }, UseHashForId = true
        };
    }

    private class LoginPageConfig
    {
        public string Label { get; set; }
        public string HomeUrl { get; set; }
        public string LoginUrl { get; set; }
        public string[] Domains { get; set; }
        public string[] AccountNameCookie { get; set; }
        public string[] AccountIdCookie { get; set; }
        public bool UseHashForId { get; set; }
        public Func<string, string> IdTransformer { get; set; }
        public string FetchNameUrl { get; set; }
        public string FetchNameParser { get; set; }
    }

    // ========== 公开入口方法 ==========

    public LoginResult ShowLoginWindow(IWin32Window owner, string platformKey, string toolDir)
    {
        LoginPageConfig config;
        if (!PlatformConfigs.TryGetValue(platformKey, out config))
        {
            return new LoginResult { Success = false, ErrorMessage = "不支持的平台：" + platformKey };
        }

        LoginResult result = null;

        var form = new LoginForm(config, toolDir, platformKey);
        form.StartPosition = FormStartPosition.CenterParent;

        form.Shown += async (s, e) =>
        {
            try
            {
                // 如果窗体在初始化完成前就被关闭了，直接返回
                if (form.IsDisposed) return;
                var userDataFolder = Path.Combine(toolDir, "_user_data", "webview2_profile");
                Directory.CreateDirectory(userDataFolder);

                var envOptions = new CoreWebView2EnvironmentOptions();
                // 使用桌面 Chrome UA，避免某些平台跳转到移动版
                // 注意：AdditionalBrowserArguments 仅在创建环境时可用
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder, envOptions);
                await form.webView.EnsureCoreWebView2Async(env);

                form.webView.CoreWebView2.Settings.UserAgent =
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
                form.webView.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = true;
                form.webView.CoreWebView2.Settings.IsPasswordAutosaveEnabled = false;

                form.initialized = true;
                form.btnDone.Enabled = true;
                form.lnkClearCache.Visible = true;
                form.lblAccountLabel.Visible = true;
                form.txtAccountName.Visible = true;
                form.lblStatus.Text = "请在浏览器窗口中完成登录。支持密码、扫码、验证码等所有方式。登录成功后点击[完成登录]。";
                form.lblStatus.ForeColor = Color.FromArgb(50, 50, 50);

                form.navStartTime = DateTime.Now;
                form.navTimeout.Start();
                form.pollTimer.Start();

                form.webView.CoreWebView2.Navigate(config.LoginUrl);
            }
            catch (Exception ex)
            {
                form.lblStatus.Text = "WebView2 初始化失败：" + ex.Message;
                form.lblStatus.ForeColor = Color.FromArgb(200, 50, 50);
                form.btnDone.Enabled = false;

                var msg = ex.Message;
                if (msg.Contains("user data folder") || msg.Contains("environment"))
                    msg = "WebView2 运行时可能未安装。请运行 Edge 浏览器或安装 WebView2 运行时。\n\n" + msg;

                result = new LoginResult { Success = false, ErrorMessage = msg };
                form.DialogResult = DialogResult.Abort;
                form.TimerClose();
            }
        };

        if (owner != null && owner.Handle != IntPtr.Zero)
        {
            form.ShowDialog(owner);
        }
        else
        {
            form.ShowDialog();
        }

        return form.FormResult ?? result ?? new LoginResult { Cancelled = true };
    }

    // ========== 登录窗口（内部类） ==========

    private class LoginForm : Form
    {
        public WebView2 webView;
        public Button btnDone;
        public Button btnCancel;
        public Button btnRefresh;
        public Label lblStatus;
        public LinkLabel lnkClearCache;
        public Panel topBar;
        public bool initialized = false;
        public TextBox txtAccountName;
        public Label lblAccountLabel;

        private LoginPageConfig config;
        private string toolDir;
        private string platformKey;
        private LoginResult result;
        public LoginResult FormResult { get { return result; } }
        public System.Windows.Forms.Timer pollTimer;
        public System.Windows.Forms.Timer navTimeout;
        public bool loginDetected = false;
        public DateTime navStartTime;

        public LoginForm(LoginPageConfig config, string toolDir, string platformKey)
        {
            this.config = config;
            this.toolDir = toolDir;
            this.platformKey = platformKey;

            this.Text = config.Label + " - 账号登录";
            this.Size = new Size(820, 680);
            this.MinimumSize = new Size(600, 480);
            this.Font = new Font("Microsoft YaHei UI", 9);
            this.Icon = null;
            this.BackColor = Color.FromArgb(250, 250, 250);

            // ---- 顶部工具栏 ----
            topBar = new Panel {
                Dock = DockStyle.Top,
                Height = 54,
                BackColor = Color.FromArgb(255, 255, 255),
                Padding = new Padding(0)
            };

            lblStatus = new Label {
                Text = "正在初始化浏览器组件...",
                Location = new Point(16, 6),
                AutoSize = false,
                Size = new Size(350, 20),
                ForeColor = Color.FromArgb(120, 120, 120),
                Font = new Font("Microsoft YaHei UI", 9)
            };

            lnkClearCache = new LinkLabel {
                Text = "清除缓存",
                Location = new Point(16, 32),
                AutoSize = true,
                Font = new Font("Microsoft YaHei UI", 8),
                LinkColor = Color.FromArgb(160, 160, 160),
                Visible = false,
                TabStop = false
            };
            lnkClearCache.LinkClicked += OnClearCache;

            lblAccountLabel = new Label {
                Text = "备注:",
                Location = new Point(370, 8),
                AutoSize = true,
                ForeColor = Color.FromArgb(150, 150, 150),
                Font = new Font("Microsoft YaHei UI", 8),
                Visible = false
            };

            txtAccountName = new TextBox {
                Location = new Point(410, 5),
                Size = new Size(100, 22),
                Font = new Font("Microsoft YaHei UI", 9),
                Visible = false,
                MaxLength = 20
            };

            btnDone = new Button {
                Text = "完成登录",
                Location = new Point(this.ClientSize.Width - 285, 10),
                Size = new Size(100, 32),
                Enabled = false,
                BackColor = Color.FromArgb(24, 144, 255),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9, FontStyle.Bold)
            };
            btnDone.FlatAppearance.BorderSize = 0;

            btnRefresh = new Button {
                Text = "刷新",
                Location = new Point(this.ClientSize.Width - 185, 10),
                Size = new Size(70, 32),
                BackColor = Color.FromArgb(240, 240, 240),
                FlatStyle = FlatStyle.Flat
            };
            btnRefresh.FlatAppearance.BorderSize = 0;

            btnCancel = new Button {
                Text = "取消",
                Location = new Point(this.ClientSize.Width - 110, 10),
                Size = new Size(70, 32),
                BackColor = Color.FromArgb(240, 240, 240),
                FlatStyle = FlatStyle.Flat
            };
            btnCancel.FlatAppearance.BorderSize = 0;

            // 锚定：右侧按钮跟随窗口大小
            btnDone.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnRefresh.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnCancel.Anchor = AnchorStyles.Top | AnchorStyles.Right;

            // 顶部栏底部分隔线
            var separator = new Label {
                Dock = DockStyle.Bottom,
                Height = 1,
                BackColor = Color.FromArgb(230, 230, 230)
            };

            topBar.Controls.AddRange(new Control[] { lblStatus, lblAccountLabel, txtAccountName, lnkClearCache, btnDone, btnRefresh, btnCancel, separator });

            // ---- WebView2 ----
            webView = new WebView2 { Dock = DockStyle.Fill };

            this.Controls.Add(webView);
            this.Controls.Add(topBar);

            // ---- 定时器 ----
            // 导航超时：30秒后如果页面还没加载好，给出提示
            navTimeout = new System.Windows.Forms.Timer { Interval = 30000 };
            navTimeout.Tick += OnNavTimeout;

            // 自动检测登录：每 4 秒轮询一次关键 cookie
            pollTimer = new System.Windows.Forms.Timer { Interval = 4000 };
            pollTimer.Tick += OnPollTick;

            // ---- 事件 ----
            btnDone.Click += OnDoneClick;
            btnCancel.Click += (s, e) => { result = new LoginResult { Cancelled = true }; this.DialogResult = DialogResult.Cancel; this.Close(); };
            btnRefresh.Click += (s, e) => { if (initialized && webView.CoreWebView2 != null) { lblStatus.Text = "正在刷新页面..."; lblStatus.ForeColor = Color.FromArgb(120, 120, 120); webView.CoreWebView2.Reload(); } };
            this.FormClosing += OnFormClosing;
            this.FormClosed += OnFormClosed;
            this.Resize += OnResize;
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (result == null) result = new LoginResult { Cancelled = true };
        }

        private void OnNavTimeout(object sender, EventArgs e)
        {
            navTimeout.Stop();
            if (loginDetected || this.IsDisposed) return;
            if (!initialized) return;

            var elapsed = (DateTime.Now - navStartTime).TotalSeconds;
            lblStatus.Text = string.Format("页面加载已 {0:0} 秒，若长时间空白请检查网络或点击刷新。", elapsed);
            lblStatus.ForeColor = Color.FromArgb(200, 150, 50);
        }

        private async void OnPollTick(object sender, EventArgs e)
        {
            if (loginDetected || this.IsDisposed || !initialized) return;
            if (webView.CoreWebView2 == null) return;

            try
            {
                // 检测关键认证 cookie
                foreach (var cookieName in config.AccountIdCookie)
                {
                    var cookies = await webView.CoreWebView2.CookieManager
                        .GetCookiesAsync("https://" + config.Domains[0]);
                    foreach (var c in cookies)
                    {
                        if (c.Name == cookieName && !string.IsNullOrEmpty(c.Value))
                        {
                            loginDetected = true;
                            navTimeout.Stop();

                            lblStatus.Text = "检测到登录状态！请点击[完成登录]提取 cookies。";
                            lblStatus.ForeColor = Color.FromArgb(40, 160, 40);
                            btnDone.BackColor = Color.FromArgb(40, 180, 40);
                            btnDone.Text = "完成登录 " + char.ConvertFromUtf32(0x2713);
                            this.Refresh();
                            return;
                        }
                    }
                }
            }
            catch { }
        }

        private void OnClearCache(object sender, LinkLabelLinkClickedEventArgs e)
        {
            try
            {
                var profileDir = Path.Combine(toolDir, "_user_data", "webview2_profile");
                if (Directory.Exists(profileDir))
                {
                    // 先清理 WebView2 的浏览数据
                    if (initialized && webView.CoreWebView2 != null)
                    {
                        webView.CoreWebView2.Profile.ClearBrowsingDataAsync(
                            CoreWebView2BrowsingDataKinds.Cookies |
                            CoreWebView2BrowsingDataKinds.LocalStorage |
                            CoreWebView2BrowsingDataKinds.CacheStorage |
                            CoreWebView2BrowsingDataKinds.AllSite);
                    }

                    // 然后删除磁盘上的 profile 目录（下次启动重新创建）
                    try { Directory.Delete(profileDir, true); } catch { }

                    lblStatus.Text = "缓存已清除，请重新登录。";
                    lblStatus.ForeColor = Color.FromArgb(50, 50, 50);
                    loginDetected = false;
                    btnDone.BackColor = Color.FromArgb(24, 144, 255);

                    // 刷新页面到登录页
                    if (initialized && webView.CoreWebView2 != null)
                        webView.CoreWebView2.Navigate(config.LoginUrl);
                }
            }
            catch (Exception ex)
            {
                lblStatus.Text = "清除缓存失败：" + ex.Message;
                lblStatus.ForeColor = Color.FromArgb(200, 50, 50);
            }
        }

        private void OnFormClosed(object sender, FormClosedEventArgs e)
        {
            // 停止所有定时器
            try { navTimeout.Stop(); navTimeout.Dispose(); } catch { }
            try { pollTimer.Stop(); pollTimer.Dispose(); } catch { }

            // 清理 WebView2 资源
            try
            {
                if (webView != null && !webView.IsDisposed)
                {
                    webView.Dispose();
                }
            }
            catch { }
            initialized = false;
        }

        private void OnResize(object sender, EventArgs e)
        {
            // 更新按钮位置（因为锚定在右侧）
            btnDone.Left = this.ClientSize.Width - 285;
            btnRefresh.Left = this.ClientSize.Width - 185;
            btnCancel.Left = this.ClientSize.Width - 110;
        }

        private bool extractingCookies = false;

        private async Task<string> FetchDisplayName(List<CookieEntry> cookies)
        {
            if (string.IsNullOrEmpty(config.FetchNameUrl)) return "";

            try
            {
                // 用提取到的 cookies 构建 Cookie 请求头
                var cookieBuilder = new StringBuilder();
                foreach (var c in cookies)
                {
                    if (cookieBuilder.Length > 0) cookieBuilder.Append("; ");
                    cookieBuilder.Append(c.Name);
                    cookieBuilder.Append("=");
                    cookieBuilder.Append(c.Value);
                }
                var cookieHeader = cookieBuilder.ToString();

                var httpRequest = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(config.FetchNameUrl);
                httpRequest.Method = "GET";
                httpRequest.Timeout = 10000;
                httpRequest.Headers["Cookie"] = cookieHeader;
                httpRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";

                using (var response = (System.Net.HttpWebResponse)(await httpRequest.GetResponseAsync()))
                using (var reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
                {
                    var body = await reader.ReadToEndAsync();
                    // 简单 JSON 解析：按路径取字段
                    var name = ExtractJsonPath(body, config.FetchNameParser);
                    if (!string.IsNullOrWhiteSpace(name))
                        return name;
                }
            }
            catch { }

            return "";
        }

        // 简单 JSON 路径解析：data.uname → 取 json["data"]["uname"]
        private static string ExtractJsonPath(string json, string path)
        {
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(path)) return "";
            try
            {
                var parts = path.Split('.');
                var current = json.Trim();
                foreach (var part in parts)
                {
                    var key = "\"" + part + "\"";
                    var keyIndex = current.IndexOf(key);
                    if (keyIndex < 0) return "";

                    // 跳到 key 后面的冒号
                    var colonIndex = current.IndexOf(':', keyIndex + key.Length);
                    if (colonIndex < 0) return "";

                    // 取后面第一个字符串值
                    var afterColon = current.Substring(colonIndex + 1).Trim();
                    if (afterColon.StartsWith("\""))
                    {
                        // 字符串值
                        var endQuote = afterColon.IndexOf('"', 1);
                        if (endQuote < 0) return "";
                        current = afterColon.Substring(0, endQuote + 1); // keep as quoted string
                    }
                    else if (afterColon.StartsWith("{"))
                    {
                        // 嵌套对象：找到匹配的 }
                        var depth = 0;
                        var objEnd = 0;
                        for (int i = 0; i < afterColon.Length; i++)
                        {
                            if (afterColon[i] == '{') depth++;
                            else if (afterColon[i] == '}') { depth--; if (depth == 0) { objEnd = i + 1; break; } }
                        }
                        if (objEnd == 0) return "";
                        current = afterColon.Substring(0, objEnd);
                    }
                    else if (afterColon.StartsWith("null") || afterColon.StartsWith("false"))
                    {
                        return "";
                    }
                    else
                    {
                        // 数字或其他值
                        var end = afterColon.IndexOfAny(new char[] { ',', '}', '\n', '\r' });
                        if (end < 0) end = afterColon.Length;
                        current = afterColon.Substring(0, end);
                    }
                }
                return current.Trim('"');
            }
            catch { return ""; }
        }

        private async void OnDoneClick(object sender, EventArgs e)
        {
            if (extractingCookies) return;
            extractingCookies = true;

            try
            {
                btnDone.Enabled = false;
                btnRefresh.Enabled = false;
                btnCancel.Enabled = false;
                lblStatus.Text = "正在获取账号信息...";
                lblStatus.ForeColor = Color.FromArgb(50, 50, 50);
                this.Refresh();

                var cookies = await ExtractCookies(config.Domains);

                if (cookies.Count == 0)
                {
                    result = new LoginResult {
                        Success = false,
                        ErrorMessage = "未提取到任何 cookies。\n\n请确认：\n1. 已在网页中完成登录\n2. 登录的是正确平台（" + config.Label + "）\n3. 登录后页面已跳转到首页"
                    };
                    this.DialogResult = DialogResult.Abort;
                    this.Close();
                    return;
                }

                var netscape = ToNetscapeFormat(cookies, config);
                string accountId = GetAccountIdentifier(config.AccountIdCookie, cookies, "unknown");

                if (config.IdTransformer != null)
                    accountId = config.IdTransformer(accountId);

                if (config.UseHashForId)
                    accountId = SimpleHash(accountId);

                // 从平台获取真实用户名
                string displayName = await FetchDisplayName(cookies);
                if (string.IsNullOrWhiteSpace(displayName))
                    displayName = GetAccountIdentifier(config.AccountNameCookie, cookies, accountId);

                // 用户手动备注优先
                string accountName = !string.IsNullOrWhiteSpace(txtAccountName.Text)
                    ? txtAccountName.Text.Trim()
                    : SanitizePart(displayName, 30);

                result = new LoginResult {
                    Success = true,
                    AccountName = SanitizePart(accountName, 40),
                    AccountId = SanitizePart(accountId, 40),
                    CookiesNetscape = netscape
                };
                this.DialogResult = DialogResult.OK;
                this.Close();
            }
            catch (Exception ex)
            {
                result = new LoginResult {
                    Success = false,
                    ErrorMessage = "Cookie 提取失败：" + ex.Message
                };
                this.DialogResult = DialogResult.Abort;
                this.Close();
            }
        }

        private async Task<List<CookieEntry>> ExtractCookies(string[] domains)
        {
            var allCookies = new List<CookieEntry>();
            var seen = new HashSet<string>();

            foreach (var domain in domains)
            {
                try
                {
                    // 获取带 www. 前缀的
                    var url1 = "https://" + domain + "/";
                    var list1 = await webView.CoreWebView2.CookieManager.GetCookiesAsync(url1);
                    foreach (var c in list1)
                    {
                        var key = c.Domain + "|" + c.Path + "|" + c.Name;
                        if (seen.Add(key))
                        {
                            allCookies.Add(new CookieEntry {
                                Domain = c.Domain,
                                IncludeSubdomains = c.Domain.StartsWith("."),
                                Path = c.Path,
                                Secure = c.IsSecure,
                                Expiration = SafeUnixTime(c.Expires),
                                Name = c.Name,
                                Value = c.Value
                            });
                        }
                    }

                    // 也尝试不带 www. 的（如果 domain 本身带 www.）
                    if (domain.StartsWith("www."))
                    {
                        var url2 = "https://" + domain.Substring(4) + "/";
                        var list2 = await webView.CoreWebView2.CookieManager.GetCookiesAsync(url2);
                        foreach (var c in list2)
                        {
                            var key = c.Domain + "|" + c.Path + "|" + c.Name;
                            if (seen.Add(key))
                            {
                                allCookies.Add(new CookieEntry {
                                    Domain = c.Domain,
                                    IncludeSubdomains = c.Domain.StartsWith("."),
                                    Path = c.Path,
                                    Secure = c.IsSecure,
                                    Expiration = SafeUnixTime(c.Expires),
                                    Name = c.Name,
                                    Value = c.Value
                                });
                            }
                        }
                    }
                }
                catch { }
            }

            // 按域名排序，确保主域名 cookies 在前
            return allCookies.OrderBy(c => c.Domain).ToList();
        }

        private string ToNetscapeFormat(List<CookieEntry> cookies, LoginPageConfig config)
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Netscape HTTP Cookie File");
            sb.AppendLine("# Platform: " + config.Label);
            sb.AppendLine("# Generated by WebView2 login helper");
            sb.AppendLine("# Keep this file private.");
            sb.AppendLine("");

            foreach (var c in cookies)
            {
                var subdomainFlag = c.IncludeSubdomains ? "TRUE" : "FALSE";
                var secureFlag = c.Secure ? "TRUE" : "FALSE";
                sb.Append(c.Domain).Append('\t');
                sb.Append(subdomainFlag).Append('\t');
                sb.Append(c.Path).Append('\t');
                sb.Append(secureFlag).Append('\t');
                sb.Append(c.Expiration).Append('\t');
                sb.Append(c.Name).Append('\t');
                sb.AppendLine(c.Value);
            }

            return sb.ToString();
        }

        private string GetAccountIdentifier(string[] cookieNames, List<CookieEntry> cookies, string fallback)
        {
            foreach (var name in cookieNames)
            {
                foreach (var c in cookies)
                {
                    if (c.Name == name && !string.IsNullOrWhiteSpace(c.Value))
                        return c.Value;
                }
            }
            return fallback;
        }

        private static string SanitizePart(string text, int maxLen)
        {
            var invalid = new char[] { '\\', '/', ':', '*', '?', '"', '<', '>', '|' };
            var result = new StringBuilder();
            foreach (var ch in text)
            {
                if (Array.IndexOf(invalid, ch) >= 0 || ch < 32) continue;
                if (char.IsWhiteSpace(ch)) { result.Append('_'); continue; }
                result.Append(ch);
                if (result.Length >= maxLen) break;
            }
            var s = result.ToString().Trim();
            return string.IsNullOrEmpty(s) ? "unknown" : s;
        }

        private static readonly DateTime UnixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        private static long SafeUnixTime(DateTime dt)
        {
            if (dt == DateTime.MinValue || dt == default(DateTime)) return 0;
            return (long)(dt.ToUniversalTime().Subtract(UnixEpoch)).TotalSeconds;
        }

        private static string SimpleHash(string text)
        {
            int hash = 0;
            foreach (var ch in text)
                hash = ((hash << 5) - hash + ch) | 0;
            return Math.Abs(hash).ToString("x");
        }

        public void TimerClose()
        {
            var t = new System.Windows.Forms.Timer { Interval = 100 };
            t.Tick += (s, e) => { t.Stop(); if (!this.IsDisposed) this.Close(); };
            t.Start();
        }
    }
}
'@
}

# ========== PowerShell 包装函数 ==========

$LoginUrls = @{
    bilibili  = "https://www.bilibili.com/"
    douyin    = "https://www.douyin.com/"
    twitter   = "https://x.com/login"
    youtube   = "https://accounts.google.com/ServiceLogin?service=youtube&hl=zh-CN"
    instagram = "https://www.instagram.com/accounts/login/"
}

function Start-WebView2Login {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Platform,

        [Parameter(Mandatory=$true)]
        [string]$ToolDir,

        [Parameter(Mandatory=$false)]
        $Owner = $null
    )

    if (-not $script:WebView2Available) {
        throw "WebView2 组件不可用。请先运行 Initialize-WebView2 并确认 external/webview2/ 下的 DLL 文件完整。"
    }

    $helper = New-Object WebView2LoginHelper
    $ownerHandle = if ($Owner -is [System.Windows.Forms.Form]) { $Owner } else { $null }

    $result = $helper.ShowLoginWindow($ownerHandle, $Platform, $ToolDir)
    return $result
}

function Save-WebView2Cookies {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Platform,

        [Parameter(Mandatory=$true)]
        [string]$AccountName,

        [Parameter(Mandatory=$true)]
        [string]$AccountId,

        [Parameter(Mandatory=$true)]
        [string]$NetscapeContent,

        [Parameter(Mandatory=$true)]
        [string]$CookieDir
    )

    $fileName = ("cookies_" + $Platform + "_" + $AccountName + "_" + $AccountId + ".txt")
    $filePath = Join-Path $CookieDir $fileName

    # 确保编码为 UTF-8 无 BOM，和原有扩展导出的一致
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($filePath, $NetscapeContent, $utf8NoBom)

    return @{
        FileName = $fileName
        FilePath = $filePath
    }
}
