# Use the NREL OpenStudio image as a base
FROM nrel/openstudio:3.6.1

# Set non-interactive mode and set timezone
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Denver

# Install tzdata and set your timezone
RUN apt-get update && apt-get install --yes tzdata \
    && ln -fs /usr/share/zoneinfo/$TZ /etc/localtime \
    && dpkg-reconfigure --frontend noninteractive tzdata

# Set the working directory in the container
WORKDIR /usr/src/app

# Copy the local code to the container
COPY . .

# Install additional dependencies
RUN apt-get update && apt-get install --yes \
    wget \
    unzip \
    python3-sphinx-rtd-theme \
    && rm -rf /var/lib/apt/lists/*

# Install Ruby dependencies with Bundler
# Note: Gemfile and Gemfile.lock should be present in your project directory
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

# Set up the container to start with an interactive shell. For development, debugging, or when you
# need an interactive environment to execute commands inside the container.
CMD ["bash"]
