# the WASM build of the runtime is completely indepedent 
# we can avoid cache invalidations by running it in an extra container
FROM parity/rust-builder:latest AS wasm_builder

WORKDIR /runtime

# Copy runtime library files
COPY ./runtime/Cargo.lock ./runtime/Cargo.toml ./
COPY ./runtime/src ./src
# Copy WASM build crate files
COPY ./runtime/build.rs ./runtime/wasm/Cargo.lock ./runtime/wasm/Cargo.toml ./wasm/
COPY ./runtime/wasm/src ./wasm/src
# FIXME: This throws an error that the env variable "OUT_DIR" is not set, see ./runtime/src/lib.rs#L9

# this container builds the portablegabi-node binary from source files, the runtime library and the WASM file built previously
FROM parity/rust-builder:latest AS builder

WORKDIR /build

# to avoid early cache invalidation, we build only dependencies first. For this we create fresh crates we are going to overwrite.
RUN USER=root cargo init --bin --name=portablegabi-node
RUN USER=root cargo new --lib --name=portablegabi-node-runtime runtime
RUN USER=root cargo new --name=portablegabi-node-node node
# overwrite cargo.toml with real files
COPY Cargo.toml Cargo.lock build.rs ./
COPY ./runtime/Cargo.toml ./runtime/Cargo.lock ./runtime/
COPY ./node/Cargo.toml ./node/build.rs ./node/

# build depedencies (and bogus source files)
RUN cargo build --release

# remove bogus build (but keep depedencies)
RUN cargo clean --release -p portablegabi-node-runtime

# copy everything over (cache invalidation will happen here)
COPY . /build
# get wasm built in previous step
# FIXME: This should probably be used
# COPY --from=wasm_builder /runtime/wasm/target/ ./runtime/wasm/target/
# build source again, dependencies are already built

RUN cargo build --release

# test
RUN cargo test --release -p portablegabi-node-runtime


FROM debian:stretch

WORKDIR /runtime

RUN apt-get -y update && \
	apt-get install -y --no-install-recommends \
	openssl \
	curl \
	libssl-dev dnsutils

# cleanup linux dependencies
RUN apt-get autoremove -y
RUN apt-get clean -y
RUN rm -rf /tmp/* /var/tmp/*

RUN mkdir -p /runtime/target/release/
COPY --from=builder /build/target/release/portablegabi-node ./target/release/portablegabi-node

RUN ls -la .

# expose node ports
EXPOSE 30333 9933 9944

# add entrypoint
ENTRYPOINT [ "/target/release/portablegabi-node" ]

# add default commands s.t. you only have to call docker run -p 9944:9944 kiltprotocol/portablegabi-node
CMD ["--dev", "--ws-port", "9944", "--ws-external"]