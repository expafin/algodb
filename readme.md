# AlgoDB - High-Frequency Trading Database

AlgoDB is a comprehensive solution for deploying and configuring PostgreSQL with TimescaleDB extension, optimized specifically for high-frequency trading data. This project provides enterprise-ready scripts for installation, configuration, and verification on AlmaLinux 9+ systems.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![TimescaleDB](https://img.shields.io/badge/TimescaleDB-FDB515?style=for-the-badge&logo=timescale&logoColor=black)
![AlmaLinux](https://img.shields.io/badge/AlmaLinux-2C6997?style=for-the-badge&logo=almalinux&logoColor=white)

## 🚀 Features

- **Automated PostgreSQL Installation**: Support for PostgreSQL 12-17, with optimized default settings
- **TimescaleDB Integration**: Hypertables for efficient time-series data storage and querying
- **Trading-Specific Optimizations**: Performance tuning for OHLCV (Open, High, Low, Close, Volume) data
- **Comprehensive Testing**: Verification and performance testing scripts included
- **Intelligent Configuration**: Detects hardware resources and configures accordingly
- **Security Hardening**: Secure default configurations and authentication methods
- **Clean Uninstallation**: Support for complete removal when needed

## 📋 Requirements

- AlmaLinux 9+ (or compatible RHEL-based distribution)
- Minimum 4 CPU cores (8+ recommended)
- Minimum 8GB RAM (16GB+ recommended for production)
- Root or sudo access
- Internet connection for package downloads

## 🔧 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/expafin/algodb.git
   cd algodb
   ```

2. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

3. Follow the interactive prompts to customize your installation.

The installation process will:
- Install PostgreSQL with TimescaleDB
- Configure the system for high-frequency trading workloads
- Set up the database schema with hypertables for OHLCV data
- Run verification and performance tests

## 💾 Database Schema

AlgoDB creates the following key tables:

- **market_data.tick_data**: Raw price and volume data
- **market_data.ohlcv**: Aggregated candle data (Open, High, Low, Close, Volume)
- **market_data.ohlcv_1min**: 1-minute continuous aggregate
- **market_data.ohlcv_5min**: 5-minute continuous aggregate

## 📚 Documentation

Refer to the `docs/postgres/quick-reference.md` file for:
- Connection information
- Common SQL commands
- Query examples for trading data
- Maintenance commands
- Performance tuning recommendations

## 🧪 Testing

The following test scripts are included:

- `tests/postgres/test-postgres.sh`: Basic PostgreSQL functionality
- `tests/postgres/test-timescaledb.sh`: TimescaleDB extension functionality
- `tests/postgres/test-performance.sh`: Performance benchmarks

Run them individually or they will be executed automatically during installation.

## 🛠️ Management Scripts

- `bin/postgres/configure-postgres.sh`: Update PostgreSQL configuration
- `bin/postgres/setup-schema.sh`: Initialize or update database schema
- `bin/postgres/uninstall-postgres.sh`: Remove PostgreSQL and all data
- `bin/postgres/verify-installation.sh`: Verify the installation status

## 🔒 Security

The default configuration:
- Restricts connections to localhost only
- Uses scram-sha-256 password encryption
- Sets up role-based access control
- Implements secure PostgreSQL defaults

To modify security settings, edit the templates in `templates/postgres/`.

## 📊 Performance Tuning

AlgoDB automatically configures PostgreSQL based on your hardware. Key optimized parameters include:

- Shared buffers
- Work memory
- Parallel workers
- Random page cost
- Effective I/O concurrency

For manual adjustments, modify `templates/postgres/postgresql.conf.template`.

## 🔄 Upgrading

To upgrade to a newer version:

1. Backup your existing data:
   ```bash
   sudo -u postgres pg_dump -Fc algodb > algodb_backup.dump
   ```

2. Run the uninstallation script but keep your data directories:
   ```bash
   sudo ./bin/postgres/uninstall-postgres.sh
   ```

3. Re-run the installation script with the new version.

## ⚙️ Environment Configuration

Configuration is stored in `/opt/.env`. Key settings can be modified using the `lib/env-manager.sh` utility.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📧 Contact

For questions or support, please open an issue on GitHub.
