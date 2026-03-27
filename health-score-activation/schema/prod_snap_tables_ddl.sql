-- public.access_history definition

-- Drop table

-- DROP TABLE public.access_history;

CREATE TABLE public.access_history (
	id uuid NOT NULL,
	restaurant_id varchar(255) NOT NULL,
	user_id varchar(255) NOT NULL,
	login varchar(255) NOT NULL,
	user_name varchar(255) NOT NULL,
	platform varchar(255) NOT NULL,
	public_ip varchar(255) NOT NULL,
	city varchar(255) NULL,
	state varchar(255) NULL,
	new_user bool NOT NULL,
	new_platform bool NOT NULL,
	new_city bool NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT access_history_pkey PRIMARY KEY (id)
);


-- public.awsdms_ddl_audit definition

-- Drop table

-- DROP TABLE public.awsdms_ddl_audit;

CREATE TABLE public.awsdms_ddl_audit (
	c_key bigserial NOT NULL,
	c_time timestamp NULL,
	c_user varchar(64) NULL,
	c_txn varchar(16) NULL,
	c_tag varchar(24) NULL,
	c_oid int4 NULL,
	c_name varchar(64) NULL,
	c_schema varchar(64) NULL,
	c_ddlqry text NULL,
	CONSTRAINT awsdms_ddl_audit_pkey PRIMARY KEY (c_key)
);


-- public.controlled_products_estoque_minimo_tmp definition

-- Drop table

-- DROP TABLE public.controlled_products_estoque_minimo_tmp;

CREATE TABLE public.controlled_products_estoque_minimo_tmp (
	restaurant_id uuid NULL,
	trading_name varchar(255) NULL,
	product_id uuid NULL,
	product_name varchar(255) NULL,
	"measurement_unit" public."measurement_unit" NULL,
	total_weight_ml_g float8 NULL,
	minimo_unit text NULL,
	total_etiquetas int8 NULL,
	converted_weight float8 NULL
);


-- public.delete_tag_observability definition

-- Drop table

-- DROP TABLE public.delete_tag_observability;

CREATE TABLE public.delete_tag_observability (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	restaurant_id uuid NOT NULL,
	restaurant_name varchar(255) NOT NULL,
	origin_type varchar(255) NOT NULL,
	tag_id uuid NOT NULL,
	user_id uuid NOT NULL,
	user_name varchar(255) NOT NULL,
	CONSTRAINT delete_tag_observability_pkey PRIMARY KEY (id)
);


-- public."groups" definition

-- Drop table

-- DROP TABLE public."groups";

CREATE TABLE public."groups" (
	trading_name varchar(255) NOT NULL,
	email varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	CONSTRAINT groups_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX group_trading_name_index ON public.groups USING btree (trading_name);


-- public.history_logs definition

-- Drop table

-- DROP TABLE public.history_logs;

CREATE TABLE public.history_logs (
	id uuid NOT NULL,
	resource public."resource_type" NOT NULL,
	"action" public."action" NOT NULL,
	"before" json NULL,
	"after" json NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	user_id uuid NOT NULL,
	user_name varchar(255) NOT NULL,
	parent_group_id uuid NULL,
	parent_brand_id uuid NULL,
	parent_restaurant_id uuid NULL,
	resource_owner_id uuid NOT NULL,
	CONSTRAINT history_logs_pkey PRIMARY KEY (id)
);


-- public.jobs_microservices definition

-- Drop table

-- DROP TABLE public.jobs_microservices;

CREATE TABLE public.jobs_microservices (
	id uuid NOT NULL,
	"data" json NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	status public."job_status" NOT NULL,
	error_message text NULL,
	"job_type" public."job_type" NOT NULL,
	job_queue_id serial4 NOT NULL,
	CONSTRAINT jobs_microservices_pkey PRIMARY KEY (id)
);


-- public.permissions definition

-- Drop table

-- DROP TABLE public.permissions;

CREATE TABLE public.permissions (
	id uuid NOT NULL,
	"type" public."permission_types" NOT NULL,
	resource public."permission_resources" NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT permissions_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX permissions_resource_key ON public.permissions USING btree (resource);


-- public.products definition

-- Drop table

-- DROP TABLE public.products;

CREATE TABLE public.products (
	"name" varchar(255) NOT NULL,
	brand varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	"inspection_type" public."inspection_type" NULL,
	owner_id varchar NULL,
	id uuid NOT NULL,
	deleted_at timestamptz(6) NULL,
	"day_validation" public."day_validation" NULL,
	details varchar(255) NULL,
	pre_registered_sif varchar(8) NULL,
	measurement_base_value float8 DEFAULT 0 NOT NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	weight float8 DEFAULT 0 NOT NULL,
	CONSTRAINT products_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_products_brand_pattern ON public.products USING gin (translate(lower((brand)::text), 'áàãâäéèêëíìîïóòõôöúùûüçñýÿøœæÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑÝŸØŒÆ'::text, 'aaaaaeeeeiiiiooooouuuucnyyooaAAAAAEEEEIIIIOOOOOUUUUCNYYOOA'::text) gin_trgm_ops) WHERE (deleted_at IS NULL);
CREATE INDEX idx_products_name_pattern ON public.products USING gin (translate(lower((name)::text), 'áàãâäéèêëíìîïóòõôöúùûüçñýÿøœæÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑÝŸØŒÆ'::text, 'aaaaaeeeeiiiiooooouuuucnyyooaAAAAAEEEEIIIIOOOOOUUUUCNYYOOA'::text) gin_trgm_ops) WHERE (deleted_at IS NULL);
CREATE INDEX pre_registered_sif_index ON public.products USING btree (pre_registered_sif);
CREATE INDEX products_brand_fts_index ON public.products USING gin (to_tsvector('english'::regconfig, (brand)::text));
CREATE INDEX products_deleted_at_index ON public.products USING btree (((timezone('UTC'::text, deleted_at))::date));
CREATE INDEX products_name_fts_index ON public.products USING gin (to_tsvector('english'::regconfig, (name)::text));


-- public.receivings_products_backup definition

-- Drop table

-- DROP TABLE public.receivings_products_backup;

CREATE TABLE public.receivings_products_backup (
	id uuid NULL,
	product_name varchar(255) NULL,
	inserted_at timestamptz(6) NULL,
	updated_at timestamptz(6) NULL,
	temperature varchar(255) NULL,
	measurement int4 NULL,
	"measurement_unit" public."measurement_unit" NULL,
	observation varchar(255) NULL,
	quantity int4 NULL,
	restaurant_product_id uuid NULL,
	receivings_id uuid NULL,
	brand varchar(255) NULL,
	shelflife_method public."shelflife_type" NULL,
	shelflife_status varchar(255) NULL,
	original_expiration timestamptz(6) NULL,
	product_batch varchar(255) NULL,
	sif varchar(255) NULL
);


-- public.report_microservices definition

-- Drop table

-- DROP TABLE public.report_microservices;

CREATE TABLE public.report_microservices (
	id uuid NOT NULL,
	status public."job_status" NOT NULL,
	url text NULL,
	process_id text NOT NULL,
	restaurant_id text NOT NULL,
	user_id text NOT NULL,
	"period" text NOT NULL,
	report_type text NOT NULL,
	error_message text NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	expiration_date timestamptz(6) NULL,
	file_name text NULL,
	CONSTRAINT report_microservices_pkey PRIMARY KEY (id)
);


-- public.sectors definition

-- Drop table

-- DROP TABLE public.sectors;

CREATE TABLE public.sectors (
	id uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT sectors_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX sectors_name_key ON public.sectors USING btree (name);


-- public.tag_infos_production definition

-- Drop table

-- DROP TABLE public.tag_infos_production;

CREATE TABLE public.tag_infos_production (
	id uuid NOT NULL,
	qrcode varchar(255) NULL,
	product_name text NULL,
	product_brand text NULL,
	employee_name text NULL,
	sif varchar(255) NULL,
	weight int4 NULL,
	"group" text NULL,
	sub_group text NULL,
	"shelflife_type" public."shelflife_type" NULL,
	"day_validation" public."day_validation" NULL,
	shelflife_status text NULL,
	inspection_stamp json NULL,
	used_expiration_algorithm bool DEFAULT false NULL,
	show_hours_on_print bool DEFAULT true NULL,
	expiration_date timestamptz(6) NULL,
	original_expiration timestamptz(6) NULL,
	print_in_group bool DEFAULT false NULL,
	status varchar(255) DEFAULT 'active'::character varying NULL,
	tags_count int4 NULL,
	tags_count_active int4 NULL,
	tags_count_removed int4 NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	employee_id uuid NOT NULL,
	product_id uuid NULL,
	restaurant_id uuid NULL,
	"display_type" public."display_type" DEFAULT 'default'::display_type NULL,
	"tag_size" public."tag_size" DEFAULT 'size_60x60'::tag_size NULL,
	details varchar(255) NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	measurement_base_value float8 DEFAULT 0 NOT NULL,
	unity_quantity float8 DEFAULT 1 NOT NULL,
	CONSTRAINT tag_infos_production_pkey PRIMARY KEY (id)
);
CREATE INDEX tag_infos_production_inserted_at_index ON public.tag_infos_production USING btree (inserted_at);
CREATE INDEX tag_infos_production_product_brand_index ON public.tag_infos_production USING btree (product_brand);
CREATE INDEX tag_infos_production_product_id_index ON public.tag_infos_production USING btree (product_id);
CREATE INDEX tag_infos_production_product_name_index ON public.tag_infos_production USING btree (product_name);
CREATE INDEX tag_infos_production_restaurant_index ON public.tag_infos_production USING btree (restaurant_id);


-- public.tags_controlado definition

-- Drop table

-- DROP TABLE public.tags_controlado;

CREATE TABLE public.tags_controlado (
	tag_id uuid NULL,
	tag_info_id uuid NULL,
	id serial4 NOT NULL,
	CONSTRAINT tags_controlado_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_tags_controlado_id ON public.tags_controlado USING btree (tag_id);
CREATE INDEX idx_tags_controlado_id1 ON public.tags_controlado USING btree (tag_info_id);


-- public.tags_controlado_recebimento definition

-- Drop table

-- DROP TABLE public.tags_controlado_recebimento;

CREATE TABLE public.tags_controlado_recebimento (
	tag_receivings_id uuid NULL,
	tag_info_receivings_id uuid NULL,
	id serial4 NOT NULL,
	CONSTRAINT tags_controlado_recebimento_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_tags_controlado_recebimento_tag_receivings_id ON public.tags_controlado_recebimento USING btree (tag_receivings_id);
CREATE INDEX idx_tags_controlado_recebimento_tag_receivings_id1 ON public.tags_controlado_recebimento USING btree (tag_info_receivings_id);


-- public.typeorm_migrations definition

-- Drop table

-- DROP TABLE public.typeorm_migrations;

CREATE TABLE public.typeorm_migrations (
	id serial4 NOT NULL,
	"timestamp" int8 NOT NULL,
	"name" varchar NOT NULL,
	CONSTRAINT "PK_a6d531d0c2edb2e7d4faaf5d789" PRIMARY KEY (id)
);


-- public.update_controlado_log definition

-- Drop table

-- DROP TABLE public.update_controlado_log;

CREATE TABLE public.update_controlado_log (
	id serial4 NOT NULL,
	tabela_atualizada varchar(50) NOT NULL,
	id_range_start int4 NOT NULL,
	id_range_end int4 NOT NULL,
	registros_afetados int4 NOT NULL,
	batch_size int4 NOT NULL,
	executed_at timestamp DEFAULT now() NULL,
	CONSTRAINT update_controlado_log_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_update_log_data ON public.update_controlado_log USING btree (executed_at);
CREATE INDEX idx_update_log_tabela ON public.update_controlado_log USING btree (tabela_atualizada);


-- public.brands definition

-- Drop table

-- DROP TABLE public.brands;

CREATE TABLE public.brands (
	trading_name varchar(255) NOT NULL,
	email varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	group_id uuid NULL,
	CONSTRAINT brands_pkey PRIMARY KEY (id),
	CONSTRAINT brands_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."groups"(id)
);
CREATE INDEX brand_group_id_index ON public.brands USING btree (group_id);
CREATE UNIQUE INDEX brand_trading_name_index ON public.brands USING btree (trading_name);


-- public.permissions_sectors definition

-- Drop table

-- DROP TABLE public.permissions_sectors;

CREATE TABLE public.permissions_sectors (
	id uuid NOT NULL,
	sector_id uuid NOT NULL,
	permission_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT permissions_sectors_pkey PRIMARY KEY (id),
	CONSTRAINT permissions_sectors_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id),
	CONSTRAINT permissions_sectors_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id)
);


-- public.restaurants definition

-- Drop table

-- DROP TABLE public.restaurants;

CREATE TABLE public.restaurants (
	trading_name varchar(255) NULL,
	cnpj varchar(255) NULL,
	phone varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	email varchar(255) NULL,
	company_name varchar(255) NULL,
	id uuid NOT NULL,
	brand_id uuid NULL,
	quota int4 NULL,
	timezone varchar(255) DEFAULT 'America/Sao_Paulo'::character varying NOT NULL,
	is_template bool DEFAULT false NOT NULL,
	deleted_at timestamptz(6) NULL,
	onboarding_completed bool DEFAULT false NULL,
	is_blocked bool DEFAULT false NULL,
	CONSTRAINT restaurants_pkey PRIMARY KEY (id),
	CONSTRAINT restaurants_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id)
);
CREATE INDEX restaurants_brand_id_index ON public.restaurants USING btree (brand_id);
CREATE UNIQUE INDEX restaurants_cnpj_index ON public.restaurants USING btree (cnpj);


-- public.shelflife_methods definition

-- Drop table

-- DROP TABLE public.shelflife_methods;

CREATE TABLE public.shelflife_methods (
	id uuid NOT NULL,
	"shelflife_type" public."shelflife_type" NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	restaurant_id uuid NOT NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT shelflife_methods_pkey PRIMARY KEY (id),
	CONSTRAINT shelflife_methods_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX shelflife_method_type_index ON public.shelflife_methods USING btree (shelflife_type);
CREATE INDEX shelflife_methods_restaurant_id_index ON public.shelflife_methods USING btree (restaurant_id);


-- public.shelflife_statuses definition

-- Drop table

-- DROP TABLE public.shelflife_statuses;

CREATE TABLE public.shelflife_statuses (
	id uuid NOT NULL,
	"name" text NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	restaurant_id uuid NOT NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT shelflife_statuses_pkey PRIMARY KEY (id),
	CONSTRAINT shelflife_statuses_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX shelflife_statuses_restaurant_id_index ON public.shelflife_statuses USING btree (restaurant_id);


-- public.users definition

-- Drop table

-- DROP TABLE public.users;

CREATE TABLE public.users (
	"name" varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	phone varchar(255) NULL,
	id uuid NOT NULL,
	restaurant_id uuid NULL,
	brand_id uuid NULL,
	group_id uuid NULL,
	"position" varchar(255) NULL,
	email varchar(255) NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT users_pkey PRIMARY KEY (id),
	CONSTRAINT users_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id),
	CONSTRAINT users_group_id_fkey FOREIGN KEY (group_id) REFERENCES public."groups"(id),
	CONSTRAINT users_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE UNIQUE INDEX users_email_key ON public.users USING btree (email);
CREATE INDEX users_restaurant_id_index ON public.users USING btree (restaurant_id);


-- public.addresses definition

-- Drop table

-- DROP TABLE public.addresses;

CREATE TABLE public.addresses (
	street varchar(255) NOT NULL,
	zipcode varchar(255) NOT NULL,
	city varchar(255) NOT NULL,
	state varchar(255) NOT NULL,
	complement varchar(255) NULL,
	"number" int4 NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	restaurant_id uuid NOT NULL,
	CONSTRAINT addresses_pkey PRIMARY KEY (id),
	CONSTRAINT addresses_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX addresses_restaurant_id_index ON public.addresses USING btree (restaurant_id);


-- public.authentications definition

-- Drop table

-- DROP TABLE public.authentications;

CREATE TABLE public.authentications (
	"role" public."users_role" NULL,
	login varchar(255) NOT NULL,
	password_hash varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	user_id uuid NOT NULL,
	first_access bool NULL,
	two_factor_hash varchar(255) NULL,
	two_factor_token_expiration timestamptz(6) NULL,
	CONSTRAINT authentications_pkey PRIMARY KEY (id),
	CONSTRAINT authentications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX authentications_login_index ON public.authentications USING btree (login);
CREATE INDEX authentications_user_id_index ON public.authentications USING btree (user_id);


-- public.brand_groups_products definition

-- Drop table

-- DROP TABLE public.brand_groups_products;

CREATE TABLE public.brand_groups_products (
	"name" varchar(255) NULL,
	description varchar(255) NULL,
	icon_name varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	brand_id uuid NOT NULL,
	parent_id uuid NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT brand_groups_products_pkey PRIMARY KEY (id),
	CONSTRAINT brand_groups_products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id),
	CONSTRAINT brand_groups_products_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.brand_groups_products(id)
);
CREATE INDEX brand_id_index ON public.brand_groups_products USING btree (brand_id);


-- public.brand_products definition

-- Drop table

-- DROP TABLE public.brand_products;

CREATE TABLE public.brand_products (
	id uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	brand_name varchar(255) NULL,
	"inspection_type" public."inspection_type" NULL,
	brand_id uuid NOT NULL,
	"day_validation" public."day_validation" NULL,
	pre_registered_sif varchar(8) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	deleted_at timestamptz(6) NULL,
	details varchar(255) NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	measurement_base_value float8 DEFAULT 0 NOT NULL,
	weight float8 DEFAULT 0 NOT NULL,
	CONSTRAINT brand_products_pkey PRIMARY KEY (id),
	CONSTRAINT brand_products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id)
);
CREATE INDEX brand_pre_registered_sif_index ON public.brand_products USING btree (pre_registered_sif);
CREATE INDEX brand_products_brand_id_index ON public.brand_products USING btree (brand_id);
CREATE INDEX brand_products_brand_name_fts_index ON public.brand_products USING gin (to_tsvector('english'::regconfig, (brand_name)::text));
CREATE INDEX brand_products_deleted_at_index ON public.brand_products USING btree (((timezone('UTC'::text, deleted_at))::date));
CREATE INDEX brand_products_name_fts_index ON public.brand_products USING gin (to_tsvector('english'::regconfig, (name)::text));


-- public.brand_shelflife_methods definition

-- Drop table

-- DROP TABLE public.brand_shelflife_methods;

CREATE TABLE public.brand_shelflife_methods (
	id uuid NOT NULL,
	"shelflife_type" public."shelflife_type" NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	brand_id uuid NOT NULL,
	CONSTRAINT brand_shelflife_methods_pkey PRIMARY KEY (id),
	CONSTRAINT brand_shelflife_methods_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id)
);
CREATE INDEX brand_shelflife_method_type_index ON public.brand_shelflife_methods USING btree (shelflife_type);
CREATE INDEX brand_shelflife_methods_brand_id_index ON public.brand_shelflife_methods USING btree (brand_id);


-- public.brand_shelflife_statuses definition

-- Drop table

-- DROP TABLE public.brand_shelflife_statuses;

CREATE TABLE public.brand_shelflife_statuses (
	id uuid NOT NULL,
	"name" text NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	brand_id uuid NOT NULL,
	CONSTRAINT brand_shelflife_statuses_pkey PRIMARY KEY (id),
	CONSTRAINT brand_shelflife_statuses_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id)
);
CREATE INDEX brand_shelflife_statuses_brand_id_index ON public.brand_shelflife_statuses USING btree (brand_id);


-- public.controlled_products definition

-- Drop table

-- DROP TABLE public.controlled_products;

CREATE TABLE public.controlled_products (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	product_id uuid NULL,
	restaurant_id uuid NULL,
	brand_product_id uuid NULL,
	inventory_min int4 DEFAULT 1 NOT NULL,
	inventory_min_unit public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	CONSTRAINT controlled_products_pkey PRIMARY KEY (id),
	CONSTRAINT controlled_products_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id) ON DELETE CASCADE,
	CONSTRAINT controlled_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
	CONSTRAINT controlled_products_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE
);
CREATE INDEX controlled_products_product_id_index ON public.controlled_products USING btree (product_id);
CREATE INDEX controlled_products_restaurant_id_index ON public.controlled_products USING btree (restaurant_id);
CREATE UNIQUE INDEX unique_activated_product_per_restaurant_constrain ON public.controlled_products USING btree (product_id, restaurant_id);


-- public.devices definition

-- Drop table

-- DROP TABLE public.devices;

CREATE TABLE public.devices (
	serial_code varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	restaurant_id uuid NOT NULL,
	"name" text NULL,
	has_wifi bool DEFAULT false NOT NULL,
	wifi_ssid text NULL,
	wifi_pass text NULL,
	eth_mac text NULL,
	wlan_mac text NULL,
	icon_name text NULL,
	printer_version text NULL,
	version_description text NULL,
	"tag_size" public."tag_size" DEFAULT 'size_60x60'::tag_size NOT NULL,
	tag_device varchar(255) NULL,
	CONSTRAINT devices_name_restaurant_id UNIQUE (name, restaurant_id),
	CONSTRAINT devices_pkey PRIMARY KEY (id),
	CONSTRAINT devices_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX devices_restaurant_id_index ON public.devices USING btree (restaurant_id);
CREATE UNIQUE INDEX devices_serial_code_index ON public.devices USING btree (serial_code);

-- Table Triggers

create trigger trg_devices_log after
insert
    or
delete
    or
update
    on
    public.devices for each row execute function ddl_monitoring.log_devices_changes();


-- public.employees definition

-- Drop table

-- DROP TABLE public.employees;

CREATE TABLE public.employees (
	"name" varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	deleted_at timestamp(0) NULL,
	id uuid NOT NULL,
	restaurant_id uuid NOT NULL,
	device_id uuid NULL,
	phone varchar(255) NULL,
	"position" varchar(255) NULL,
	CONSTRAINT employees_pkey PRIMARY KEY (id),
	CONSTRAINT employees_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL,
	CONSTRAINT employees_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX employees_restaurant_id_index ON public.employees USING btree (restaurant_id);


-- public.enable_feature definition

-- Drop table

-- DROP TABLE public.enable_feature;

CREATE TABLE public.enable_feature (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	count_products bool DEFAULT false NOT NULL,
	restaurant_id uuid NOT NULL,
	controlled_products bool DEFAULT false NOT NULL,
	receivings bool DEFAULT false NOT NULL,
	production_tags bool DEFAULT false NOT NULL,
	label_manipulation bool DEFAULT false NOT NULL,
	portioning bool DEFAULT false NOT NULL,
	CONSTRAINT enable_feature_pkey PRIMARY KEY (id),
	CONSTRAINT enable_feature_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE UNIQUE INDEX enable_feature_restaurant_id_key ON public.enable_feature USING btree (restaurant_id);


-- public.inventory_list definition

-- Drop table

-- DROP TABLE public.inventory_list;

CREATE TABLE public.inventory_list (
	id uuid NOT NULL,
	icon_name varchar(255) NULL,
	deleted_at timestamptz(6) NULL,
	restaurant_id uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NULL,
	updated_at timestamptz(6) NULL,
	CONSTRAINT inventory_list_pkey PRIMARY KEY (id),
	CONSTRAINT inventory_list_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX inventory_list_restaurant_id_index ON public.inventory_list USING btree (restaurant_id);


-- public.inventory_list_products definition

-- Drop table

-- DROP TABLE public.inventory_list_products;

CREATE TABLE public.inventory_list_products (
	id uuid NOT NULL,
	icon_name varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NULL,
	deleted_at timestamptz(6) NULL,
	restored_at timestamptz(6) NULL,
	product_id uuid NOT NULL,
	inventory_list_id uuid NOT NULL,
	CONSTRAINT inventory_list_products_pkey PRIMARY KEY (id),
	CONSTRAINT inventory_list_products_inventory_list_id_fkey FOREIGN KEY (inventory_list_id) REFERENCES public.inventory_list(id),
	CONSTRAINT inventory_list_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
CREATE INDEX inventory_list_products_inventory_list_id_index ON public.inventory_list_products USING btree (inventory_list_id);
CREATE INDEX inventory_list_products_product_id_index ON public.inventory_list_products USING btree (product_id);


-- public.monitoring_quota definition

-- Drop table

-- DROP TABLE public.monitoring_quota;

CREATE TABLE public.monitoring_quota (
	id uuid NOT NULL,
	tags_count int4 NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	"period" date NOT NULL,
	restaurant_id uuid NULL,
	quota int4 NULL,
	CONSTRAINT monitoring_quota_pkey PRIMARY KEY (id),
	CONSTRAINT monitoring_quota_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX monitoring_quota_period_index ON public.monitoring_quota USING btree (period);
CREATE UNIQUE INDEX unique_period_per_restaurant ON public.monitoring_quota USING btree (restaurant_id, period);


-- public.receivings definition

-- Drop table

-- DROP TABLE public.receivings;

CREATE TABLE public.receivings (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	user_id uuid NULL,
	employee_id uuid NULL,
	employee_name varchar(255) NULL,
	restaurant_id uuid NOT NULL,
	invoice varchar(255) NULL,
	CONSTRAINT receivings_pkey PRIMARY KEY (id),
	CONSTRAINT receivings_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL,
	CONSTRAINT receivings_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT receivings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
);


-- public.registration_print_configs definition

-- Drop table

-- DROP TABLE public.registration_print_configs;

CREATE TABLE public.registration_print_configs (
	id uuid NOT NULL,
	"day_validation" public."day_validation" DEFAULT 'consider_full_day'::day_validation NOT NULL,
	default_display_hours_and_minutes bool DEFAULT true NOT NULL,
	default_print_hours bool DEFAULT true NOT NULL,
	show_hours_on_print bool DEFAULT true NOT NULL,
	show_minutes_on_print bool DEFAULT true NOT NULL,
	restaurant_id uuid NOT NULL,
	show_restaurant_info_on_print bool DEFAULT true NOT NULL,
	enabled_preview public._tag_size DEFAULT ARRAY['size_60x60'::tag_size] NULL,
	CONSTRAINT registration_print_configs_pkey PRIMARY KEY (id),
	CONSTRAINT registration_print_configs_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE UNIQUE INDEX registration_print_configs_restaurant_id_key ON public.registration_print_configs USING btree (restaurant_id);


-- public.reports definition

-- Drop table

-- DROP TABLE public.reports;

CREATE TABLE public.reports (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	"name" varchar(255) NULL,
	"group" varchar(255) NULL,
	subgroup varchar(255) NULL,
	user_id uuid NULL,
	employee_id uuid NULL,
	employee_name varchar(255) NULL,
	restaurant_id uuid NOT NULL,
	CONSTRAINT reports_pkey PRIMARY KEY (id),
	CONSTRAINT reports_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL,
	CONSTRAINT reports_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
);


-- public.restaurant_brand_product_not_in definition

-- Drop table

-- DROP TABLE public.restaurant_brand_product_not_in;

CREATE TABLE public.restaurant_brand_product_not_in (
	id uuid NOT NULL,
	brand_id uuid NOT NULL,
	restaurant_id uuid NOT NULL,
	brand_product_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT restaurant_brand_product_not_in_pkey PRIMARY KEY (id),
	CONSTRAINT restaurant_brand_product_not_in_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id),
	CONSTRAINT restaurant_brand_product_not_in_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id),
	CONSTRAINT restaurant_brand_product_not_in_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX restaurant_brand_product_not_in_brand_id_index ON public.restaurant_brand_product_not_in USING btree (brand_id);
CREATE INDEX restaurant_brand_product_not_in_brand_product_id_index ON public.restaurant_brand_product_not_in USING btree (brand_product_id);
CREATE INDEX restaurant_brand_product_not_in_restaurant_id_index ON public.restaurant_brand_product_not_in USING btree (restaurant_id);


-- public.restaurant_groups definition

-- Drop table

-- DROP TABLE public.restaurant_groups;

CREATE TABLE public.restaurant_groups (
	"name" varchar(255) NULL,
	description varchar(255) NULL,
	icon_name varchar(255) NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	restaurant_id uuid NOT NULL,
	parent_id uuid NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT restaurant_groups_pkey PRIMARY KEY (id),
	CONSTRAINT restaurant_groups_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.restaurant_groups(id),
	CONSTRAINT restaurant_groups_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX restaurant_groups_restaurant_id_index ON public.restaurant_groups USING btree (restaurant_id);


-- public.restaurant_products definition

-- Drop table

-- DROP TABLE public.restaurant_products;

CREATE TABLE public.restaurant_products (
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	product_id uuid NULL,
	restaurant_id uuid NULL,
	CONSTRAINT restaurant_products_pkey PRIMARY KEY (id),
	CONSTRAINT restaurant_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
	CONSTRAINT restaurant_products_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX restaurant_products_product_id_index ON public.restaurant_products USING btree (product_id);
CREATE INDEX restaurant_products_restaurant_id_index ON public.restaurant_products USING btree (restaurant_id);
CREATE UNIQUE INDEX unique_activated_product_per_restaurant ON public.restaurant_products USING btree (product_id, restaurant_id);


-- public.shelflife_categories definition

-- Drop table

-- DROP TABLE public.shelflife_categories;

CREATE TABLE public.shelflife_categories (
	days int4 DEFAULT 0 NOT NULL,
	"type" text NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	product_id uuid NOT NULL,
	restaurant_id uuid NULL,
	hours int4 DEFAULT 0 NOT NULL,
	minutes int4 DEFAULT 0 NOT NULL,
	show_hours_on_print bool DEFAULT false NOT NULL,
	shelflife_methods_id uuid NULL,
	shelflife_statuses_id uuid NULL,
	status text NULL,
	"display_type" public."display_type" DEFAULT 'default'::display_type NOT NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT shelflife_categories_pkey PRIMARY KEY (id),
	CONSTRAINT shelflife_categories_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
	CONSTRAINT shelflife_categories_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT shelflife_categories_shelflife_methods_id_fkey FOREIGN KEY (shelflife_methods_id) REFERENCES public.shelflife_methods(id),
	CONSTRAINT shelflife_categories_shelflife_statuses_id_fkey FOREIGN KEY (shelflife_statuses_id) REFERENCES public.shelflife_statuses(id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX shelflife_categories_product_id_index ON public.shelflife_categories USING btree (product_id);
CREATE INDEX shelflife_categories_restaurant_id_index ON public.shelflife_categories USING btree (restaurant_id);


-- public.shelflife_methods_statuses definition

-- Drop table

-- DROP TABLE public.shelflife_methods_statuses;

CREATE TABLE public.shelflife_methods_statuses (
	id text NOT NULL,
	shelflife_method_id uuid NOT NULL,
	shelflife_status_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT shelflife_methods_statuses_pkey PRIMARY KEY (id),
	CONSTRAINT shelflife_methods_statuses_shelflife_method_id_fkey FOREIGN KEY (shelflife_method_id) REFERENCES public.shelflife_methods(id) ON DELETE CASCADE,
	CONSTRAINT shelflife_methods_statuses_shelflife_status_id_fkey FOREIGN KEY (shelflife_status_id) REFERENCES public.shelflife_statuses(id) ON DELETE CASCADE
);
CREATE INDEX shelflife_methods_statuses_shelflife_method_id_index ON public.shelflife_methods_statuses USING btree (shelflife_method_id);
CREATE INDEX shelflife_methods_statuses_shelflife_status_id_index ON public.shelflife_methods_statuses USING btree (shelflife_status_id);


-- public.tag_infos definition

-- Drop table

-- DROP TABLE public.tag_infos;

CREATE TABLE public.tag_infos (
	expiration_date timestamptz(6) NULL,
	qrcode varchar(255) NULL,
	"shelflife_type" public."shelflife_type" NULL,
	inspection_stamp json NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	sif varchar(255) NULL,
	weight int4 NULL,
	id uuid NOT NULL,
	product_id uuid NULL,
	restaurant_id uuid NULL,
	employee_id uuid NOT NULL,
	"day_validation" public."day_validation" NULL,
	show_hours_on_print bool DEFAULT true NULL,
	"group" text NULL,
	sub_group text NULL,
	original_expiration timestamptz(6) NULL,
	shelflife_status text NULL,
	used_expiration_algorithm bool DEFAULT false NULL,
	employee_name text NULL,
	product_brand text NULL,
	product_name text NULL,
	print_in_group bool DEFAULT false NULL,
	tags_count int4 NULL,
	tags_count_active int4 NULL,
	tags_count_removed int4 NULL,
	status varchar(255) DEFAULT 'active'::character varying NULL,
	"display_type" public."display_type" DEFAULT 'default'::display_type NULL,
	"tag_size" public."tag_size" DEFAULT 'size_60x60'::tag_size NULL,
	details varchar(255) NULL,
	measurement_base_value float8 DEFAULT 0 NOT NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	brand_product_id uuid NULL,
	deleted_at timestamptz(6) NULL,
	controlled_product bool DEFAULT false NOT NULL,
	origin_ip varchar(255) NULL,
	origin_user_agent varchar(255) NULL,
	CONSTRAINT tag_infos_pkey PRIMARY KEY (id),
	CONSTRAINT tag_infos_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id),
	CONSTRAINT tag_infos_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id),
	CONSTRAINT tag_infos_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
	CONSTRAINT tag_infos_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE INDEX idx_restaurant_date_shelflife ON public.tag_infos USING btree (restaurant_id, expiration_date, shelflife_type, shelflife_status);
CREATE INDEX idx_tag_infos_inserted_at ON public.tag_infos USING btree (inserted_at);
CREATE INDEX idx_tag_infos_restaurant_date ON public.tag_infos USING btree (restaurant_id, inserted_at);
CREATE INDEX idx_tag_infos_restaurant_id_date ON public.tag_infos USING btree (restaurant_id, ((timezone('UTC'::text, inserted_at))::date));
CREATE INDEX tag_infos_brand_product_id_index ON public.tag_infos USING btree (brand_product_id);
CREATE INDEX tag_infos_expiration_date_index ON public.tag_infos USING btree (expiration_date);
CREATE INDEX tag_infos_id_index ON public.tag_infos USING btree (id) WHERE (controlled_product = true);
CREATE INDEX tag_infos_product_id_index ON public.tag_infos USING btree (product_id);
CREATE INDEX tag_infos_product_name_index ON public.tag_infos USING btree (product_name);
CREATE UNIQUE INDEX tag_infos_qrcode_index ON public.tag_infos USING btree (qrcode);
CREATE INDEX tag_infos_restaurant_index ON public.tag_infos USING btree (restaurant_id);
CREATE INDEX tag_infos_shelflife_type_index ON public.tag_infos USING btree (shelflife_type);
CREATE INDEX tag_infos_status_index ON public.tag_infos USING btree (status);


-- public.tag_infos_receivings definition

-- Drop table

-- DROP TABLE public.tag_infos_receivings;

CREATE TABLE public.tag_infos_receivings (
	id uuid NOT NULL,
	qrcode varchar(255) NULL,
	product_name text NULL,
	product_brand text NULL,
	employee_name text NULL,
	sif varchar(255) NULL,
	weight int4 NULL,
	"group" text NULL,
	sub_group text NULL,
	"shelflife_type" public."shelflife_type" NULL,
	"day_validation" public."day_validation" NULL,
	shelflife_status text NULL,
	inspection_stamp json NULL,
	used_expiration_algorithm bool DEFAULT false NULL,
	show_hours_on_print bool DEFAULT true NULL,
	expiration_date timestamptz(6) NULL,
	original_expiration timestamptz(6) NULL,
	print_in_group bool DEFAULT false NULL,
	status varchar(255) DEFAULT 'active'::character varying NULL,
	tags_count int4 NULL,
	tags_count_active int4 NULL,
	tags_count_removed int4 NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	employee_id uuid NULL,
	product_id uuid NULL,
	restaurant_id uuid NULL,
	"display_type" public."display_type" DEFAULT 'default'::display_type NULL,
	"tag_size" public."tag_size" DEFAULT 'size_60x60'::tag_size NULL,
	details varchar(255) NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	measurement_base_value float8 DEFAULT 0 NOT NULL,
	user_id uuid NULL,
	product_batch varchar(255) NULL,
	used_original_expiration bool DEFAULT false NOT NULL,
	controlled_product bool DEFAULT false NOT NULL,
	origin_ip varchar(255) NULL,
	origin_user_agent varchar(255) NULL,
	CONSTRAINT tag_infos_receivings_pkey PRIMARY KEY (id),
	CONSTRAINT tag_infos_receivings_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id),
	CONSTRAINT tag_infos_receivings_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
	CONSTRAINT tag_infos_receivings_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT tag_infos_receivings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE INDEX tag_infos_receivings_expiration_date_index ON public.tag_infos_receivings USING btree (expiration_date);
CREATE INDEX tag_infos_receivings_id_index ON public.tag_infos_receivings USING btree (id) WHERE (controlled_product = true);
CREATE INDEX tag_infos_receivings_product_id_index ON public.tag_infos_receivings USING btree (product_id);
CREATE INDEX tag_infos_receivings_product_name_index ON public.tag_infos_receivings USING btree (product_name);
CREATE UNIQUE INDEX tag_infos_receivings_qrcode_index ON public.tag_infos_receivings USING btree (qrcode);
CREATE INDEX tag_infos_receivings_restaurant_index ON public.tag_infos_receivings USING btree (restaurant_id);
CREATE INDEX tag_infos_receivings_shelflife_type_index ON public.tag_infos_receivings USING btree (shelflife_type);
CREATE INDEX tag_infos_receivings_status_index ON public.tag_infos_receivings USING btree (status);


-- public.tags definition

-- Drop table

-- DROP TABLE public.tags;

CREATE TABLE public.tags (
	status varchar(255) DEFAULT 'active'::character varying NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	tag_info_id uuid NULL,
	restaurant_id uuid NULL,
	id_search text GENERATED ALWAYS AS (id::text) STORED NULL,
	deleted_at timestamptz(6) NULL,
	controlled_product bool DEFAULT false NOT NULL,
	CONSTRAINT tags_pkey PRIMARY KEY (id),
	CONSTRAINT tags_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT tags_tag_info_id_fkey FOREIGN KEY (tag_info_id) REFERENCES public.tag_infos(id)
)
WITH (
	autovacuum_analyze_scale_factor=0.05,
	autovacuum_analyze_threshold=1000
);
CREATE INDEX tag_infos_index ON public.tags USING btree (tag_info_id);
CREATE INDEX tags_id_index ON public.tags USING btree (id) WHERE (controlled_product = true);
CREATE INDEX tags_id_search_idx ON public.tags USING gin (id_search gin_trgm_ops);
CREATE INDEX tags_inserted_index ON public.tags USING btree (((timezone('UTC'::text, inserted_at))::date));
CREATE INDEX tags_restaurant_id_index ON public.tags USING btree (restaurant_id);
CREATE INDEX tags_status_index ON public.tags USING btree (status);


-- public.tags_receivings definition

-- Drop table

-- DROP TABLE public.tags_receivings;

CREATE TABLE public.tags_receivings (
	status varchar(255) DEFAULT 'active'::character varying NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	tag_info_receivings_id uuid NULL,
	restaurant_id uuid NULL,
	id_search text GENERATED ALWAYS AS (id::text) STORED NULL,
	controlled_product bool DEFAULT false NOT NULL,
	CONSTRAINT tags_receivings_pkey PRIMARY KEY (id),
	CONSTRAINT tags_receivings_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
	CONSTRAINT tags_receivings_tag_info_receivings_id_fkey FOREIGN KEY (tag_info_receivings_id) REFERENCES public.tag_infos_receivings(id)
);
CREATE INDEX tag_infos_receivings_index ON public.tags_receivings USING btree (tag_info_receivings_id);
CREATE INDEX tags_receivings_id_index ON public.tags_receivings USING btree (id) WHERE (controlled_product = true);
CREATE INDEX tags_receivings_id_search_idx ON public.tags_receivings USING gin (id_search gin_trgm_ops);
CREATE INDEX tags_receivings_restaurant_id_index ON public.tags_receivings USING btree (restaurant_id);
CREATE INDEX tags_receivings_status_index ON public.tags_receivings USING btree (status);


-- public.user_sectors definition

-- Drop table

-- DROP TABLE public.user_sectors;

CREATE TABLE public.user_sectors (
	id uuid NOT NULL,
	user_id uuid NOT NULL,
	sector_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT user_sectors_pkey PRIMARY KEY (id),
	CONSTRAINT user_sectors_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id),
	CONSTRAINT user_sectors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);


-- public.brand_groups_products_relation definition

-- Drop table

-- DROP TABLE public.brand_groups_products_relation;

CREATE TABLE public.brand_groups_products_relation (
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	brand_groups_product_id uuid NULL,
	brand_product_id uuid NULL,
	CONSTRAINT brand_groups_products_relation_pkey PRIMARY KEY (id),
	CONSTRAINT brand_groups_products_relation_brand_groups_product_id_fkey FOREIGN KEY (brand_groups_product_id) REFERENCES public.brand_groups_products(id),
	CONSTRAINT brand_groups_products_relation_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id)
);
CREATE INDEX brand_group_products_brand_group_id_index ON public.brand_groups_products_relation USING btree (brand_groups_product_id);
CREATE INDEX brand_group_products_brand_product_id_index ON public.brand_groups_products_relation USING btree (brand_product_id);


-- public.brand_shelflife_categories definition

-- Drop table

-- DROP TABLE public.brand_shelflife_categories;

CREATE TABLE public.brand_shelflife_categories (
	id uuid NOT NULL,
	days int4 DEFAULT 0 NOT NULL,
	hours int4 DEFAULT 0 NOT NULL,
	minutes int4 DEFAULT 0 NOT NULL,
	"type" text NOT NULL,
	status text NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	show_hours_on_print bool DEFAULT false NOT NULL,
	brand_product_id uuid NOT NULL,
	brand_id uuid NULL,
	brand_shelflife_methods_id uuid NULL,
	brand_shelflife_statuses_id uuid NULL,
	"display_type" public."display_type" DEFAULT 'default'::display_type NOT NULL,
	CONSTRAINT brand_shelflife_categories_pkey PRIMARY KEY (id),
	CONSTRAINT brand_shelflife_categories_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES public.brands(id),
	CONSTRAINT brand_shelflife_categories_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id),
	CONSTRAINT brand_shelflife_categories_brand_shelflife_methods_id_fkey FOREIGN KEY (brand_shelflife_methods_id) REFERENCES public.brand_shelflife_methods(id),
	CONSTRAINT brand_shelflife_categories_brand_shelflife_statuses_id_fkey FOREIGN KEY (brand_shelflife_statuses_id) REFERENCES public.brand_shelflife_statuses(id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX brand_shelflife_categories_brand_id_index ON public.brand_shelflife_categories USING btree (brand_id);
CREATE INDEX brand_shelflife_categories_brand_product_id_index ON public.brand_shelflife_categories USING btree (brand_product_id);


-- public.brand_shelflife_methods_statuses definition

-- Drop table

-- DROP TABLE public.brand_shelflife_methods_statuses;

CREATE TABLE public.brand_shelflife_methods_statuses (
	id text NOT NULL,
	brand_shelflife_method_id uuid NOT NULL,
	brand_shelflife_status_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	CONSTRAINT brand_shelflife_methods_statuses_pkey PRIMARY KEY (id),
	CONSTRAINT brand_shelflife_methods_statuses_brand_shelflife_method_id_fkey FOREIGN KEY (brand_shelflife_method_id) REFERENCES public.brand_shelflife_methods(id) ON DELETE CASCADE,
	CONSTRAINT brand_shelflife_methods_statuses_brand_shelflife_status_id_fkey FOREIGN KEY (brand_shelflife_status_id) REFERENCES public.brand_shelflife_statuses(id) ON DELETE CASCADE
);
CREATE INDEX brand_shelflife_methods_statuses_brand_shelflife_method_id_inde ON public.brand_shelflife_methods_statuses USING btree (brand_shelflife_method_id);
CREATE INDEX brand_shelflife_methods_statuses_brand_shelflife_status_id_inde ON public.brand_shelflife_methods_statuses USING btree (brand_shelflife_status_id);


-- public.controlled_products_history definition

-- Drop table

-- DROP TABLE public.controlled_products_history;

CREATE TABLE public.controlled_products_history (
	id uuid NOT NULL,
	tag_id uuid NULL,
	product_id uuid NULL,
	product_name varchar(255) NOT NULL,
	product_group varchar(255) NULL,
	product_sub_group varchar(255) NULL,
	product_method varchar(255) NOT NULL,
	product_unit varchar(255) NOT NULL,
	product_weight float8 DEFAULT 0 NOT NULL,
	status public."controlled_products_status" NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	restaurant_id uuid NOT NULL,
	received_tag_id uuid NULL,
	product_status varchar(255) NULL,
	brand_product_id uuid NULL,
	product_brand varchar(255) NULL,
	CONSTRAINT controlled_products_history_pkey PRIMARY KEY (id),
	CONSTRAINT controlled_products_history_brand_product_id_fkey FOREIGN KEY (brand_product_id) REFERENCES public.brand_products(id),
	CONSTRAINT controlled_products_history_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
	CONSTRAINT controlled_products_history_received_tag_id_fkey FOREIGN KEY (received_tag_id) REFERENCES public.tags_receivings(id),
	CONSTRAINT controlled_products_history_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE,
	CONSTRAINT controlled_products_history_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id)
);
CREATE INDEX controlled_products_history_product_id_index ON public.controlled_products_history USING btree (product_id);
CREATE INDEX controlled_products_history_received_tag_id_index ON public.controlled_products_history USING btree (received_tag_id);
CREATE INDEX controlled_products_history_restaurant_id_index ON public.controlled_products_history USING btree (restaurant_id);
CREATE INDEX controlled_products_history_tag_id_index ON public.controlled_products_history USING btree (tag_id);


-- public.inventory definition

-- Drop table

-- DROP TABLE public.inventory;

CREATE TABLE public.inventory (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	"name" varchar(255) NULL,
	user_id uuid NULL,
	employee_id uuid NULL,
	employee_name varchar(255) NULL,
	restaurant_id uuid NOT NULL,
	inventory_list_id uuid NULL,
	completed_at timestamptz(6) NULL,
	deleted_at timestamptz(6) NULL,
	CONSTRAINT inventory_pkey PRIMARY KEY (id),
	CONSTRAINT inventory_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id),
	CONSTRAINT inventory_inventory_list_id_fkey FOREIGN KEY (inventory_list_id) REFERENCES public.inventory_list(id),
	CONSTRAINT inventory_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE,
	CONSTRAINT inventory_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
);
CREATE INDEX inventory_employee_id_index ON public.inventory USING btree (employee_id);
CREATE INDEX inventory_list_id_index ON public.inventory USING btree (inventory_list_id);
CREATE INDEX inventory_restaurant_id_index ON public.inventory USING btree (restaurant_id);
CREATE INDEX inventory_user_id_index ON public.inventory USING btree (user_id);


-- public.inventory_count definition

-- Drop table

-- DROP TABLE public.inventory_count;

CREATE TABLE public.inventory_count (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	product_id uuid NULL,
	product_name varchar(255) NULL,
	"group" varchar(255) NULL,
	subgroup varchar(255) NULL,
	brand varchar(255) NULL,
	status varchar(255) NULL,
	unit varchar(255) NULL,
	count int4 DEFAULT 0 NULL,
	weight float8 DEFAULT 0 NULL,
	"method" varchar(255) NULL,
	observation varchar(255) NULL,
	inventory_id uuid NOT NULL,
	tag_id uuid NULL,
	received_tag_id uuid NULL,
	CONSTRAINT inventory_count_pkey PRIMARY KEY (id),
	CONSTRAINT inventory_count_inventory_id_fkey FOREIGN KEY (inventory_id) REFERENCES public.inventory(id) ON DELETE CASCADE,
	CONSTRAINT inventory_count_received_tag_id_fkey FOREIGN KEY (received_tag_id) REFERENCES public.tags_receivings(id),
	CONSTRAINT inventory_count_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id)
);
CREATE INDEX inventory_count_inventory_id_index ON public.inventory_count USING btree (inventory_id);
CREATE INDEX inventory_count_product_id_index ON public.inventory_count USING btree (product_id);
CREATE INDEX inventory_count_received_tag_id_index ON public.inventory_count USING btree (received_tag_id);
CREATE INDEX inventory_count_tag_id_index ON public.inventory_count USING btree (tag_id);


-- public.portioning definition

-- Drop table

-- DROP TABLE public.portioning;

CREATE TABLE public.portioning (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	quantity int4 DEFAULT 1 NOT NULL,
	tag_info_id uuid NOT NULL,
	CONSTRAINT portioning_pkey PRIMARY KEY (id),
	CONSTRAINT portioning_tag_info_id_fkey FOREIGN KEY (tag_info_id) REFERENCES public.tag_infos(id)
);
CREATE UNIQUE INDEX portioning_tag_info_id_key ON public.portioning USING btree (tag_info_id);


-- public.products_count_reports definition

-- Drop table

-- DROP TABLE public.products_count_reports;

CREATE TABLE public.products_count_reports (
	id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	product varchar(255) NULL,
	brand varchar(255) NULL,
	status varchar(255) NULL,
	unit varchar(255) NULL,
	count int4 DEFAULT 0 NULL,
	"method" varchar(255) NULL,
	observation varchar(255) NULL,
	report_id uuid NOT NULL,
	CONSTRAINT products_count_reports_pkey PRIMARY KEY (id),
	CONSTRAINT products_count_reports_report_id_fkey FOREIGN KEY (report_id) REFERENCES public.reports(id)
);


-- public.receivings_products definition

-- Drop table

-- DROP TABLE public.receivings_products;

CREATE TABLE public.receivings_products (
	id uuid NOT NULL,
	product_name varchar(255) NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	temperature varchar(255) NULL,
	measurement int4 DEFAULT 0 NOT NULL,
	"measurement_unit" public."measurement_unit" DEFAULT 'g'::measurement_unit NOT NULL,
	observation varchar(255) NULL,
	quantity int4 DEFAULT 0 NOT NULL,
	restaurant_product_id uuid NOT NULL,
	receivings_id uuid NOT NULL,
	brand varchar(255) NULL,
	shelflife_method public."shelflife_type" NULL,
	shelflife_status varchar(255) NULL,
	original_expiration timestamptz(6) NULL,
	product_batch varchar(255) NULL,
	sif varchar(255) NULL,
	controlled_receiving bool DEFAULT false NULL,
	CONSTRAINT receivings_products_pkey PRIMARY KEY (id),
	CONSTRAINT receivings_products_receivings_id_fkey FOREIGN KEY (receivings_id) REFERENCES public.receivings(id),
	CONSTRAINT receivings_products_restaurant_product_id_fkey FOREIGN KEY (restaurant_product_id) REFERENCES public.restaurant_products(id)
);


-- public.restaurant_group_products definition

-- Drop table

-- DROP TABLE public.restaurant_group_products;

CREATE TABLE public.restaurant_group_products (
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated_at timestamptz(6) NOT NULL,
	id uuid NOT NULL,
	restaurant_group_id uuid NULL,
	restaurant_product_id uuid NULL,
	CONSTRAINT restaurant_group_products_pkey PRIMARY KEY (id),
	CONSTRAINT restaurant_group_products_restaurant_group_id_fkey FOREIGN KEY (restaurant_group_id) REFERENCES public.restaurant_groups(id),
	CONSTRAINT restaurant_group_products_restaurant_product_id_fkey FOREIGN KEY (restaurant_product_id) REFERENCES public.restaurant_products(id)
);
CREATE INDEX restaurant_group_products_restaurant_group_id_index ON public.restaurant_group_products USING btree (restaurant_group_id);
CREATE INDEX restaurant_group_products_restaurant_product_id_index ON public.restaurant_group_products USING btree (restaurant_product_id);


-- public.tag_manipulations_history definition

-- Drop table

-- DROP TABLE public.tag_manipulations_history;

CREATE TABLE public.tag_manipulations_history (
	id uuid NOT NULL,
	previous_tag_infos_id uuid NOT NULL,
	next_tag_infos_id uuid NOT NULL,
	previous_tag_id uuid NOT NULL,
	next_tag_id uuid NOT NULL,
	inserted_at timestamptz(6) DEFAULT CURRENT_TIMESTAMP NOT NULL,
	user_id uuid NULL,
	employee_id uuid NULL,
	previous_tag_type public."manipulated_tag_type" DEFAULT 'production'::manipulated_tag_type NOT NULL,
	CONSTRAINT tag_manipulations_history_pkey PRIMARY KEY (id),
	CONSTRAINT tag_manipulations_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id),
	CONSTRAINT tag_manipulations_history_next_tag_id_fkey FOREIGN KEY (next_tag_id) REFERENCES public.tags(id),
	CONSTRAINT tag_manipulations_history_next_tag_infos_id_fkey FOREIGN KEY (next_tag_infos_id) REFERENCES public.tag_infos(id),
	CONSTRAINT tag_manipulations_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE INDEX tag_manipulation_history_employee_id_index ON public.tag_manipulations_history USING btree (employee_id);
CREATE INDEX tag_manipulation_history_next_tag_id_index ON public.tag_manipulations_history USING btree (next_tag_id);
CREATE INDEX tag_manipulation_history_next_tag_infos_id_index ON public.tag_manipulations_history USING btree (next_tag_infos_id);
CREATE INDEX tag_manipulation_history_previous_tag_id_index ON public.tag_manipulations_history USING btree (previous_tag_id);
CREATE INDEX tag_manipulation_history_previous_tag_infos_id_index ON public.tag_manipulations_history USING btree (previous_tag_infos_id);
CREATE INDEX tag_manipulation_history_user_id_index ON public.tag_manipulations_history USING btree (user_id);
CREATE UNIQUE INDEX tag_manipulations_history_next_tag_id_key ON public.tag_manipulations_history USING btree (next_tag_id);