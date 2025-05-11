from pyinfra.operations import apk, openrc, postgres

from components import concourse
from operations import alpine

USER = "atc"

alpine.set_timezone()
alpine.set_repository(version="3.21")
alpine.enable_community_repository()
# alpine.enable_edge_repository()
# alpine.enable_testing_repository()

alpine.install_tooling()


apk.packages(
    name="Installing Postgres 16",
    packages=["postgresql16", "postgresql16-contrib", "postgresql16-openrc"],
)

openrc.service(
    name="Activate Postgres", service="postgresql", running=True, enabled=True
)

# Create the database for Concourse under the name ATC
postgres.role(
    name="Create ATC role",
    role="atc",
    present=True,
    psql_user="postgres",
)
postgres.database(
    name="Create ATC database",
    database="atc",
    present=True,
    owner="atc",
    psql_user="postgres",
)


concourse.install_concourse()
concourse.setup_services()
concourse.first_run()
concourse.start_web()
concourse.start_worker()
