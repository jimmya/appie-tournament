import Vapor
import App
import VaporPostgreSQL
import VaporAPNS

let drop = Droplet()

try drop.addProvider(VaporPostgreSQL.Provider.self)
drop.view = LeafRenderer(viewsDir: drop.viewsDir)

var apns: VaporAPNS? = nil
do {
    var options = try Options(topic: drop.config["apns", "topic"]?.string ?? "",
                              teamId: drop.config["apns", "teamId"]?.string ?? "",
                              keyId: drop.config["apns", "keyId"]?.string ?? "",
                              keyPath: "\(drop.resourcesDir)/Certificates/APNS.p8")
    options.disableCurlCheck = true
    apns = try VaporAPNS(options: options)
    drop.log.info("Vapor APNS initialised")
} catch let e {
    drop.log.error("Error initialising Vapor APNS \(e)")
}

let configuration = Configuration(viewRenderer: drop.view,
                                  localization: drop.localization,
                                  logger: drop.log,
                                  apns: apns)
configureRoutes(router: drop, configuration: configuration)
configurePreparations(preparations: &drop.preparations)
configureMiddleware(middleware: &drop.middleware)

drop.run()
