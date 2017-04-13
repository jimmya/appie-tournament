import Vapor
import App
import VaporPostgreSQL
import Flash

let drop = Droplet()

try drop.addProvider(VaporPostgreSQL.Provider.self)
drop.view = LeafRenderer(viewsDir: drop.viewsDir)

let configuration = Configuration(viewRenderer: drop.view,
                                  localization: drop.localization,
                                  logger: drop.log)
configureRoutes(router: drop, configuration: configuration)
configurePreparations(preparations: &drop.preparations)
configureMiddleware(middleware: &drop.middleware)

drop.run()
