FROM eddpt/swift-docker-postgresql

ADD ./ /app
WORKDIR /app

RUN swift build --configuration release

ENV PATH /app/.build/release:$PATH

RUN chmod -R a+w /app && chmod -R 777 /app

RUN useradd -m myuser
USER myuser

CMD .build/release/Executable --env=test --workdir="/app" --config:servers.default.port=$PORT --config:postgresql.url=$DATABASE_URL --config:apns.topic=$APNS_TOPIC --config:apns.teamId=$APNS_TEAM_ID --config:apns.keyId=$APNS_KEY_ID
