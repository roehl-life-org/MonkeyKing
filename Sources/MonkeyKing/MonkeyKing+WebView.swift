
import UIKit
import WebKit

extension MonkeyKing: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Swift.Error) {
        // Pocket OAuth
        if let errorString = (error as NSError).userInfo["ErrorFailingURLStringKey"] as? String, errorString.hasSuffix(":authorizationFinished") {
            removeWebView(webView, with: .success(nil))
            return
        }
        // Failed to connect network
        activityIndicatorViewAction(webView, stop: true)
        addCloseButton()
        let detailLabel = UILabel()
        detailLabel.text = "无法连接，请检查网络后重试"
        detailLabel.textColor = UIColor.gray
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        let centerX = NSLayoutConstraint(item: detailLabel, attribute: .centerX, relatedBy: .equal, toItem: webView, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let centerY = NSLayoutConstraint(item: detailLabel, attribute: .centerY, relatedBy: .equal, toItem: webView, attribute: .centerY, multiplier: 1.0, constant: -50.0)
        webView.addSubview(detailLabel)
        webView.addConstraints([centerX, centerY])
        webView.scrollView.alwaysBounceVertical = false
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicatorViewAction(webView, stop: true)
        addCloseButton()
        guard let host = webView.url?.host else { return }
        var scriptString = ""
        switch host {
        case "getpocket.com":
            scriptString += "document.querySelector('div.toolbar').style.display = 'none';"
            scriptString += "document.querySelector('a.extra_action').style.display = 'none';"
            scriptString += "var rightButton = $('.toolbarContents div:last-child');"
            scriptString += "if (rightButton.html() == 'Log In') {rightButton.click()}"
        case "api.weibo.com":
            scriptString += "document.querySelector('aside.logins').style.display = 'none';"
        default:
            break
        }
        webView.evaluateJavaScript(scriptString, completionHandler: nil)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else {
            webView.stopLoading()
            return
        }
        // twitter access token
        for case .twitter(let appID, let appKey, let redirectURL) in accountSet {
            guard url.absoluteString.hasPrefix(redirectURL) else { break }
            let params = url.monkeyking_queryDictionary
            guard let token = params["oauth_token"], let verifer = params["oauth_verifier"] else { break }
            let accessTokenAPI = "https://api.twitter.com/oauth/access_token"
            let parameters = ["oauth_token": token, "oauth_verifier": verifer]
            let headerString = Networking.shared.authorizationHeader(for: .post, urlString: accessTokenAPI, appID: appID, appKey: appKey, accessToken: nil, accessTokenSecret: nil, parameters: parameters, isMediaUpload: false)
            let oauthHeader = ["Authorization": headerString]
            request(accessTokenAPI, method: .post, parameters: nil, encoding: .url, headers: oauthHeader) { [weak self] responseData, _, error in
                DispatchQueue.main.async { [weak self] in
                    let result: Result<ResponseJSON?, Error>
                    if error != nil {
                        result = .failure(.apiRequest(.unrecognizedError(error: error, response: responseData)))
                    } else {
                        result = .success(responseData)
                    }
                    self?.removeWebView(webView, with: result)
                }
            }
            return
        }
        // QQ Web OAuth
        guard url.absoluteString.contains("&access_token="), url.absoluteString.contains("qq.com") else {
            return
        }
        guard let fragment = url.fragment?.dropFirst(), let newURL = URL(string: "https://qzs.qq.com/?\(String(fragment))") else {
            return
        }
        let queryDictionary = newURL.monkeyking_queryDictionary as [String: Any]
        removeWebView(webView, with: .success(queryDictionary))
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // WeChat OAuth
        if url.absoluteString.hasPrefix("wx") {
            let queryDictionary = url.monkeyking_queryDictionary
            guard let code = queryDictionary["code"] else {
                return
            }
            MonkeyKing.fetchWeChatOAuthInfoByCode(code: code) { [weak self] result in
                self?.removeWebView(webView, with: result)
            }
        } else {
            // Weibo OAuth
            for case .weibo(_, _, let redirectURL, _) in accountSet {
                if url.absoluteString.hasPrefix(redirectURL) {
                    guard let code = url.monkeyking_queryDictionary["code"] else { return }
                    MonkeyKing.fetchWeiboOAuthInfoByCode(code: code) { [weak self] result in
                        self?.removeWebView(webView, with: result)
                    }
                }
            }
        }
    }
}

extension MonkeyKing {

    class func generateWebView() -> WKWebView {
        let webView = WKWebView()
        let screenBounds = UIScreen.main.bounds
        webView.frame = CGRect(
            origin: CGPoint(x: 0, y: screenBounds.height),
            size: CGSize(width: screenBounds.width, height: screenBounds.height - 20)
        )
        webView.navigationDelegate = shared
        webView.backgroundColor = UIColor(red: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow })?.addSubview(webView)
        return webView
    }

    class func addWebView(withURLString urlString: String) {
        if MonkeyKing.shared.webView == nil {
            MonkeyKing.shared.webView = generateWebView()
        }
        guard let url = URL(string: urlString), let webView = MonkeyKing.shared.webView else { return }
        webView.load(URLRequest(url: url))
        let activityIndicatorView = UIActivityIndicatorView(frame: CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0))
        activityIndicatorView.center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY + 30.0)
        activityIndicatorView.style = .medium
        webView.scrollView.addSubview(activityIndicatorView)
        activityIndicatorView.startAnimating()
        UIView.animate(withDuration: 0.32, delay: 0.0, options: .curveEaseOut, animations: {
            webView.frame.origin.y = 20.0
        }, completion: nil)
    }

    func addCloseButton() {
        guard let webView = webView else { return }
        let closeButton = CloseButton(type: .custom)
        closeButton.frame = CGRect(
            origin: CGPoint(x: UIScreen.main.bounds.width - 50.0, y: 4.0),
            size: CGSize(width: 44.0, height: 44.0)
        )
        closeButton.addTarget(self, action: #selector(closeOauthView), for: .touchUpInside)
        webView.addSubview(closeButton)
    }

    @objc func closeOauthView() {
        guard let webView = webView else { return }
        removeWebView(webView, with: .failure(.userCancelled))
    }

    func removeWebView(_ webView: WKWebView, with result: Result<ResponseJSON?, Error>) {
        activityIndicatorViewAction(webView, stop: true)
        webView.stopLoading()
        UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseOut, animations: {
            webView.frame.origin.y = UIScreen.main.bounds.height
        }, completion: { [weak self] _ in
            webView.removeFromSuperview()
            MonkeyKing.shared.webView = nil
            self?.oauthCompletionHandler?(result)
        })
    }

    func activityIndicatorViewAction(_ webView: WKWebView, stop: Bool) {
        for subview in webView.scrollView.subviews {
            if let activityIndicatorView = subview as? UIActivityIndicatorView {
                guard stop else {
                    activityIndicatorView.startAnimating()
                    return
                }
                activityIndicatorView.stopAnimating()
            }
        }
    }
}

class CloseButton: UIButton {
    override func draw(_ rect: CGRect) {
        let circleWidth: CGFloat = 28.0
        let circlePathX = (rect.width - circleWidth) / 2.0
        let circlePathY = (rect.height - circleWidth) / 2.0
        let circlePathRect = CGRect(x: circlePathX, y: circlePathY, width: circleWidth, height: circleWidth)
        let circlePath = UIBezierPath(ovalIn: circlePathRect)
        UIColor(white: 0.8, alpha: 1.0).setFill()
        circlePath.fill()
        let xPath = UIBezierPath()
        xPath.lineCapStyle = .round
        xPath.lineWidth = 3.0
        let offset: CGFloat = (bounds.width - circleWidth) / 2.0
        xPath.move(to: CGPoint(x: offset + circleWidth / 3.0, y: offset + circleWidth / 3.0))
        xPath.addLine(to: CGPoint(x: offset + 2.0 * circleWidth / 3.0, y: offset + 2.0 * circleWidth / 3.0))
        xPath.move(to: CGPoint(x: offset + circleWidth / 3.0, y: offset + 2.0 * circleWidth / 3.0))
        xPath.addLine(to: CGPoint(x: offset + 2.0 * circleWidth / 3.0, y: offset + circleWidth / 3.0))
        UIColor.white.setStroke()
        xPath.stroke()
    }
}
