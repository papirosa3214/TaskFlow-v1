// BackgroundKeepAlive.swift
// Не даёт системе усыпить приложение, пока в островке висит задача.
//
// ЗАЧЕМ ЭТО ВООБЩЕ НУЖНО. Островок рисует не приложение, а система, и
// двигать карточку можно только двумя путями: из работающего приложения
// через ActivityKit, либо пушем через APNs. Второй путь требует платного
// аккаунта разработчика (проверено 10.09.2026: с `pushType: .token`
// ActivityKit отвечает `PermissionsError Code=3`). Первый упирается в то,
// что свёрнутое приложение не выполняется вовсе.
//
// Отсюда обход: пока карточка висит, приложение объявляет себя работающим
// с геопозицией и остаётся живым — держит связь с сервером и двигает
// островок само.
//
// ЧЕСТНАЯ ЦЕНА. Батарея садится быстрее, в статусной строке индикатор.
// Поэтому фон живёт РОВНО пока висит островок: включается вместе с ним,
// гаснет вместе с ним. Отдельного переключателя нет сознательно — владелец
// 10.09.2026: «я же всё равно сам нажимаю, какую задачу показать; она
// прошла, я выключил. Одну задачу раз в сто лет».
//
// ⚠️ ТОЧНОСТЬ НЕЛЬЗЯ ВЫКРУЧИВАТЬ В САМУЮ ГРУБУЮ, хотя соблазн есть.
//
// Первая версия (10.09.2026) ставила `kCLLocationAccuracyThreeKilometers`
// и порог смещения 3 км — «геопозиция нам не нужна, лишь бы фон жил».
// На живом телефоне индикатор горел пару минут и гас: телефон лежит на
// столе, смещения нет, событий нет — системе нечего доставлять, и она
// усыпляет приложение. Островок замирал ровно так же, как до всей затеи.
//
// Живым фон держат ПОСТУПАЮЩИЕ события, а не сам факт включённого
// менеджера. Поэтому порог убран совсем, а точность — «ближайшие сто
// метров»: события идут регулярно даже от лежащего телефона, при этом это
// не самый жадный режим (`Best` гоняет GPS постоянно и греет заметно
// сильнее).

import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeepAlive()

    private let manager = CLLocationManager()
    private var isRunning = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // kCLDistanceFilterNone — события приходят независимо от того,
        // двигался телефон или лежал: именно они и держат фон живым.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Разрешение спрашиваем ровно в этот момент, а не при запуске
        // приложения: человек должен понимать, за что его спрашивают.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        Diag.log("[KeepAlive] фон включён — островок будет живым")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        Diag.log("[KeepAlive] фон выключен")
    }

    /// Координаты нам не нужны — важен сам факт события: пока они идут,
    /// приложение не спит. Считаем их, чтобы в логе было видно, живёт фон
    /// или система нас усыпила.
    private var tick = 0

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        tick += 1
        if tick % 10 == 0 {
            Diag.log("[KeepAlive] фон жив, событий: %d")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Diag.log("[KeepAlive] геопозиция отказала: %@")
    }
}
