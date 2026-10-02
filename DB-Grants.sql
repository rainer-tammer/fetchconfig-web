\c fetchconfig
GRANT SELECT, INSERT, UPDATE, DELETE ON sites      TO fetchconfig;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_sites TO fetchconfig;
GRANT USAGE, SELECT, UPDATE         ON SEQUENCE sites_id_seq TO fetchconfig;
