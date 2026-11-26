//
//  Logging.swift
//  NASA APOD
//
//  Same role as in BingWallpaper: one place for the OSLog subsystem
//  and categories. The subsystem follows this app's bundle id.
//

class Logging {
    private init() { }

    static let subsystem = "com.otakun.NASAApod"

    enum Category: String {
        case Settings
        case Download
        case FileHandler
        case Wallpaper
        case AppUpdate
        case Menu
        case Service
    }
}
