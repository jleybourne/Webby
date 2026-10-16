//
//  ContentBlocker.swift
//  Webby
//
//  Network-level ad & tracker blocking. The legacy WebKit engine honours
//  registered URLProtocols, so blocked requests are failed before a single
//  byte leaves the Apple TV — pages load faster and use less memory.
//

import Foundation

extension Notification.Name {
    static let contentBlockerDidBlock = Notification.Name("WebbyContentBlockerDidBlock")
}

final class ContentBlocker: URLProtocol {

    private static let lock = NSLock()
    private static var _isEnabled = true

    static var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isEnabled }
        set { lock.lock(); _isEnabled = newValue; lock.unlock() }
    }

    static func install(enabled: Bool) {
        isEnabled = enabled
        URLProtocol.registerClass(ContentBlocker.self)
    }

    /// Returns true when `host` or any parent domain is on the block list.
    static func shouldBlock(host: String) -> Bool {
        var candidate = Substring(host.lowercased())
        while true {
            if blockedDomains.contains(String(candidate)) { return true }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = candidate[candidate.index(after: dot)...]
            if !candidate.contains(".") { return false }
        }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard isEnabled,
              let url = request.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        // Never block the page the user explicitly navigated to.
        if let main = request.mainDocumentURL, main == url { return false }
        return shouldBlock(host: host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let page = request.mainDocumentURL
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contentBlockerDidBlock, object: nil,
                                            userInfo: page.map { ["page": $0] } ?? [:])
        }
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled,
                            userInfo: [NSLocalizedDescriptionKey: "Blocked by Webby"])
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}

    // MARK: Block list

    static let blockedDomains: Set<String> = [
        // Ad networks
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "adnxs.com", "adsrvr.org",
        "advertising.com", "amazon-adsystem.com", "criteo.com", "criteo.net", "taboola.com",
        "outbrain.com", "revcontent.com", "mgid.com", "pubmatic.com", "rubiconproject.com",
        "openx.net", "casalemedia.com", "indexww.com", "smartadserver.com", "teads.tv",
        "media.net", "contextweb.com", "sharethrough.com", "triplelift.com", "yieldmo.com",
        "33across.com", "gumgum.com", "adform.net", "adition.com", "bidswitch.net",
        "spotxchange.com", "spotx.tv", "springserve.com", "lijit.com", "sovrn.com",
        "zedo.com", "adtech.de", "yieldlab.net", "rlcdn.com", "adsafeprotected.com",
        "moatads.com", "doubleverify.com", "serving-sys.com", "flashtalking.com",
        "innovid.com", "imasdk.googleapis.com", "popads.net", "popcash.net", "propellerads.com",
        "adcash.com", "exoclick.com", "juicyads.com", "trafficjunky.net", "adsterra.com",
        "hilltopads.net", "admaven.com", "clickadu.com", "infolinks.com", "buysellads.com",
        "carbonads.net", "adroll.com", "quantserve.com", "quantcount.com", "zergnet.com",
        "yahoo-ads.com", "ads.yahoo.com", "advertising.yahoo.com", "ads.twitter.com",
        "ads-twitter.com", "ads.linkedin.com", "adsymptotic.com", "unrulymedia.com",
        "undertone.com", "kargo.com", "districtm.io", "emxdgt.com", "onetag-sys.com",
        "smaato.net", "inmobi.com", "applovin.com", "unityads.unity3d.com", "vungle.com",
        "chartboost.com", "ironsrc.com", "adcolony.com", "mopub.com",
        // Analytics & trackers
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "ssl.google-analytics.com", "analytics.google.com", "stats.g.doubleclick.net",
        "scorecardresearch.com", "comscore.com", "chartbeat.com", "chartbeat.net",
        "hotjar.com", "hotjar.io", "mouseflow.com", "crazyegg.com", "fullstory.com",
        "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "heapanalytics.com",
        "kissmetrics.com", "optimizely.com", "newrelic.com", "nr-data.net", "bugsnag.com",
        "branch.io", "app-measurement.com", "adjust.com", "appsflyer.com", "kochava.com",
        "bluekai.com", "krxd.net", "demdex.net", "omtrdc.net", "everesttech.net",
        "exelator.com", "eyeota.net", "tapad.com", "agkn.com", "mathtag.com",
        "addthis.com", "addthisedge.com", "sharethis.com", "bounceexchange.com",
        "connect.facebook.net", "pixel.facebook.com", "an.facebook.com", "analytics.tiktok.com",
        "ads.tiktok.com", "bat.bing.com", "clarity.ms", "pixel.wp.com", "stats.wp.com",
        "yandex.ru", "mc.yandex.ru", "an.yandex.ru", "statcounter.com", "histats.com",
        "luckyorange.com", "inspectlet.com", "clicktale.net", "contentsquare.net",
        "permutive.com", "parsely.com", "parse.ly", "piano.io", "tinypass.com",
        "cxense.com", "gemius.pl", "webtrends.com", "omniture.com", "2o7.net",
        "coremetrics.com", "tealiumiq.com", "tiqcdn.com", "ensighten.com",
        "onesignal.com", "pushcrew.com", "pushwoosh.com", "subscribers.com",
        "liadm.com", "id5-sync.com", "crwdcntrl.net", "adsymptotic.net", "zemanta.com",
    ]
}
