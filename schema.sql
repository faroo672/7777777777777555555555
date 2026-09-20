-- Samee Perfume E-Commerce Database Schema
-- Run this in Supabase SQL Editor

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================================
-- ROLES & PERMISSIONS
-- ============================================================
create table if not exists admin_roles (
  id uuid primary key default uuid_generate_v4(),
  name text unique not null,
  label text not null,
  permissions jsonb default '[]'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

insert into admin_roles (name, label, permissions) values
('super_admin', 'Super Admin', '["all"]'),
('admin', 'Admin', '["products.read","products.write","orders.read","orders.write","users.read","reviews.read","reviews.write","settings.read","settings.write","content.write"]'),
('product_manager', 'Product Manager', '["products.read","products.write","categories.read","categories.write","inventory.write"]'),
('order_manager', 'Order Manager', '["orders.read","orders.write","refunds.read","refunds.write"]'),
('support_manager', 'Support Manager', '["users.read","reviews.read","reviews.write","orders.read"]'),
('content_manager', 'Content Manager', '["content.write","pages.write","banners.write","settings.read"]')
on conflict (name) do nothing;

-- ============================================================
-- PROFILES (extends auth.users)
-- ============================================================
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  role text default 'customer' check (role in ('customer','super_admin','admin','product_manager','order_manager','support_manager','content_manager')),
  language_preference text default 'en',
  is_active boolean default true,
  last_active_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Auto-create profile on signup
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    coalesce(new.raw_user_meta_data ->> 'role', 'customer')
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================
-- CATEGORIES
-- ============================================================
create table if not exists categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,
  description text,
  image_url text,
  parent_id uuid references categories(id) on delete set null,
  sort_order integer default 0,
  is_active boolean default true,
  seo_title text,
  seo_description text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- PRODUCTS
-- ============================================================
create table if not exists products (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,
  short_description text,
  description text,
  price decimal(10,2) not null,
  sale_price decimal(10,2),
  discount_percent integer default 0,
  sku text,
  barcode text,
  category_id uuid references categories(id) on delete set null,
  brand text,
  fragrance_type text,
  size text,
  volume text,
  stock_quantity integer default 0,
  low_stock_threshold integer default 5,
  is_active boolean default true,
  is_featured boolean default false,
  is_bestseller boolean default false,
  is_new_arrival boolean default false,
  average_rating decimal(3,2) default 0,
  total_reviews integer default 0,
  total_sold integer default 0,
  whatsapp_order_enabled boolean default true,
  seo_title text,
  seo_description text,
  tags text[],
  meta jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- PRODUCT IMAGES
-- ============================================================
create table if not exists product_images (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  url text not null,
  alt_text text,
  sort_order integer default 0,
  is_primary boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- PRODUCT VARIANTS
-- ============================================================
create table if not exists product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  name text not null,
  sku text,
  price decimal(10,2) not null,
  sale_price decimal(10,2),
  stock_quantity integer default 0,
  size text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ============================================================
-- CART
-- ============================================================
create table if not exists carts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  session_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists cart_items (
  id uuid primary key default uuid_generate_v4(),
  cart_id uuid references carts(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  variant_id uuid references product_variants(id) on delete set null,
  quantity integer default 1,
  created_at timestamptz default now(),
  unique(cart_id, product_id, variant_id)
);

-- ============================================================
-- WISHLIST
-- ============================================================
create table if not exists wishlists (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, product_id)
);

-- ============================================================
-- ORDERS
-- ============================================================
create table if not exists orders (
  id uuid primary key default uuid_generate_v4(),
  order_number text unique not null,
  user_id uuid references profiles(id) on delete set null,
  guest_email text,
  guest_phone text,
  status text default 'pending' check (status in (
    'pending','payment_pending','paid','confirmed','processing',
    'shipped','delivered','cancelled','refund_pending','refunded','payment_failed'
  )),
  subtotal decimal(10,2) not null default 0,
  discount_amount decimal(10,2) default 0,
  shipping_fee decimal(10,2) default 0,
  total decimal(10,2) not null default 0,
  currency text default 'PKR',
  payment_method text,
  payment_status text default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  payment_reference text,
  shipping_name text,
  shipping_phone text,
  shipping_email text,
  shipping_address text,
  shipping_city text,
  shipping_area text,
  shipping_postal_code text,
  order_notes text,
  coupon_code text,
  coupon_discount decimal(10,2) default 0,
  cancellation_reason text,
  refund_reason text,
  refund_amount decimal(10,2) default 0,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- ORDER ITEMS
-- ============================================================
create table if not exists order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  product_image text,
  variant_name text,
  quantity integer not null default 1,
  price decimal(10,2) not null,
  total decimal(10,2) not null,
  created_at timestamptz default now()
);

-- ============================================================
-- PAYMENTS
-- ============================================================
create table if not exists payments (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references orders(id) on delete cascade,
  method text not null,
  amount decimal(10,2) not null,
  currency text default 'PKR',
  status text default 'pending' check (status in ('pending','completed','failed','refunded')),
  transaction_id text,
  gateway_response jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- REFUNDS
-- ============================================================
create table if not exists refunds (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references orders(id) on delete set null,
  amount decimal(10,2) not null,
  reason text,
  status text default 'pending' check (status in ('pending','approved','rejected','completed')),
  requested_by uuid references profiles(id),
  approved_by uuid references profiles(id),
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- REVIEWS
-- ============================================================
create table if not exists reviews (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  user_id uuid references profiles(id) on delete set null,
  rating integer not null check (rating >= 1 and rating <= 5),
  title text,
  comment text,
  image_url text,
  is_approved boolean default false,
  is_featured boolean default false,
  admin_reply text,
  helpful_count integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
create table if not exists notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  type text not null,
  title text not null,
  message text,
  link text,
  is_read boolean default false,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- ============================================================
-- USER ACTIVITY LOG
-- ============================================================
create table if not exists user_activity (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete set null,
  action text not null,
  details jsonb default '{}'::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz default now()
);

-- ============================================================
-- LANGUAGES
-- ============================================================
create table if not exists languages (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,
  name text not null,
  native_name text,
  is_rtl boolean default false,
  is_active boolean default true,
  is_default boolean default false,
  sort_order integer default 0,
  created_at timestamptz default now()
);

-- Default languages
insert into languages (code, name, native_name, is_rtl, is_active, is_default, sort_order) values
('en', 'English', 'English', false, true, true, 1),
('ur', 'Urdu', 'اردو', true, true, false, 2),
('ar', 'Arabic', 'العربية', true, true, false, 3),
('ps', 'Pashto', 'پښتو', true, true, false, 4),
('sd', 'Sindhi', 'سنڌي', true, true, false, 5),
('pa', 'Punjabi', 'ਪੰਜਾਬੀ', false, true, false, 6),
('skr', 'Saraiki', 'سرائیکی', false, true, false, 7),
('khw', 'Khowar', 'کھوار', false, true, false, 8),
('bal', 'Balochi', 'بلوچی', true, true, false, 9),
('fa', 'Persian', 'فارسی', true, true, false, 10)
on conflict (code) do nothing;

-- ============================================================
-- TRANSLATIONS
-- ============================================================
create table if not exists translations (
  id uuid primary key default uuid_generate_v4(),
  language_code text not null references languages(code) on delete cascade,
  key text not null,
  value text not null,
  namespace text default 'common',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(language_code, key, namespace)
);

-- ============================================================
-- WEBSITE SETTINGS
-- ============================================================
create table if not exists website_settings (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  value jsonb not null,
  category text default 'general',
  is_public boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Default settings
insert into website_settings (key, value, category, is_public) values
('site_name', '"Samee Perfume"', 'brand', true),
('site_tagline', '"Premium Perfumes & Attars"', 'brand', true),
('logo_url', 'null', 'brand', true),
('favicon_url', 'null', 'brand', true),
('primary_color', '"#d97706"', 'theme', true),
('secondary_color', '"#1f2937"', 'theme', true),
('accent_color', '"#fbbf24"', 'theme', true),
('font_family', '"Inter"', 'theme', true),
('whatsapp_number', '"923001234567"', 'contact', true),
('support_email', '"support@sameeperfume.com"', 'contact', true),
('support_phone', '"+923001234567"', 'contact', true),
('facebook_url', 'null', 'social', true),
('instagram_url', 'null', 'social', true),
('tiktok_url', 'null', 'social', true),
('youtube_url', 'null', 'social', true),
('twitter_url', 'null', 'social', true),
('telegram_url', 'null', 'social', true),
('default_currency', '"PKR"', 'payment', true),
('currency_symbol', '"Rs"', 'payment', true),
('shipping_fee', '250', 'shipping', true),
('free_shipping_threshold', '5000', 'shipping', true),
('meta_title', '"Samee Perfume - Premium Perfumes & Attars"', 'seo', true),
('meta_description', '"Shop premium perfumes, attars, and fragrances at Samee Perfume. Best quality, best prices." ' , 'seo', true),
('maintenance_mode', 'false', 'general', false)
on conflict (key) do nothing;

-- ============================================================
-- MENU ITEMS
-- ============================================================
create table if not exists menu_items (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  url text,
  sort_order integer default 0,
  is_active boolean default true,
  parent_id uuid references menu_items(id) on delete cascade,
  section text default 'header' check (section in ('header','footer','dot_menu')),
  opens_new_tab boolean default false,
  icon text,
  created_at timestamptz default now()
);

-- Default menu items
insert into menu_items (label, url, sort_order, section) values
('Home', '/', 1, 'header'),
('Products', '/products', 2, 'header'),
('Categories', '/categories', 3, 'header'),
('About Us', '/about', 4, 'header'),
('Contact Us', '/contact', 5, 'header'),
('Home', '/', 1, 'footer'),
('Products', '/products', 2, 'footer'),
('About Us', '/about', 3, 'footer'),
('Contact Us', '/contact', 4, 'footer'),
('Privacy Policy', '/privacy-policy', 5, 'footer'),
('Terms & Conditions', '/terms', 6, 'footer'),
('Shipping Policy', '/shipping-policy', 7, 'footer'),
('Return Policy', '/return-policy', 8, 'footer'),
('Refund Policy', '/refund-policy', 9, 'footer'),
('Home', '/', 1, 'dot_menu'),
('Products', '/products', 2, 'dot_menu'),
('Categories', '/categories', 3, 'dot_menu'),
('My Account', '/account', 4, 'dot_menu'),
('My Orders', '/account/orders', 5, 'dot_menu'),
('Wishlist', '/account/wishlist', 6, 'dot_menu'),
('Settings', '/account/settings', 7, 'dot_menu'),
('Contact Us', '/contact', 8, 'dot_menu'),
('About Us', '/about', 9, 'dot_menu'),
('Help / FAQ', '/help', 10, 'dot_menu'),
('Privacy Policy', '/privacy-policy', 11, 'dot_menu'),
('Terms & Conditions', '/terms', 12, 'dot_menu'),
('Logout', '/auth/logout', 13, 'dot_menu');

-- ============================================================
-- SOCIAL LINKS
-- ============================================================
create table if not exists social_links (
  id uuid primary key default uuid_generate_v4(),
  platform text not null,
  url text not null,
  is_active boolean default true,
  sort_order integer default 0,
  created_at timestamptz default now()
);

-- ============================================================
-- COUPONS
-- ============================================================
create table if not exists coupons (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,
  discount_type text default 'percentage' check (discount_type in ('percentage','fixed')),
  discount_value decimal(10,2) not null,
  minimum_order decimal(10,2) default 0,
  maximum_discount decimal(10,2),
  usage_limit integer,
  used_count integer default 0,
  user_limit integer,
  is_active boolean default true,
  expires_at timestamptz,
  created_at timestamptz default now()
);

-- ============================================================
-- BANNERS
-- ============================================================
create table if not exists banners (
  id uuid primary key default uuid_generate_v4(),
  title text,
  subtitle text,
  image_url text,
  link_url text,
  button_text text,
  sort_order integer default 0,
  is_active boolean default true,
  position text default 'hero' check (position in ('hero','promo','sidebar')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- ADMIN AUDIT LOG
-- ============================================================
create table if not exists admin_audit_log (
  id uuid primary key default uuid_generate_v4(),
  admin_id uuid references profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  ip_address text,
  created_at timestamptz default now()
);

-- ============================================================
-- PASSWORD RECOVERY TOKENS
-- ============================================================
create table if not exists password_recovery_tokens (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  token text not null,
  method text check (method in ('email','sms','whatsapp')),
  expires_at timestamptz not null,
  used boolean default false,
  attempts integer default 0,
  created_at timestamptz default now()
);

-- ============================================================
-- INDEXES
-- ============================================================
create index if not exists idx_products_category on products(category_id);
create index if not exists idx_products_slug on products(slug);
create index if not exists idx_products_active on products(is_active);
create index if not exists idx_products_featured on products(is_featured);
create index if not exists idx_products_bestseller on products(is_bestseller);
create index if not exists idx_products_new on products(is_new_arrival);
create index if not exists idx_product_images_product on product_images(product_id);
create index if not exists idx_orders_user on orders(user_id);
create index if not exists idx_orders_status on orders(status);
create index if not exists idx_orders_number on orders(order_number);
create index if not exists idx_cart_items_cart on cart_items(cart_id);
create index if not exists idx_wishlists_user on wishlists(user_id);
create index if not exists idx_reviews_product on reviews(product_id);
create index if not exists idx_reviews_user on reviews(user_id);
create index if not exists idx_notifications_user on notifications(user_id);
create index if not exists idx_user_activity_user on user_activity(user_id);
create index if not exists idx_translations_lang on translations(language_code);
create index if not exists idx_settings_key on website_settings(key);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table profiles enable row level security;
alter table products enable row level security;
alter table categories enable row level security;
alter table product_images enable row level security;
alter table product_variants enable row level security;
alter table carts enable row level security;
alter table cart_items enable row level security;
alter table wishlists enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table payments enable row level security;
alter table refunds enable row level security;
alter table reviews enable row level security;
alter table notifications enable row level security;
alter table user_activity enable row level security;
alter table translations enable row level security;
alter table website_settings enable row level security;
alter table menu_items enable row level security;
alter table social_links enable row level security;
alter table coupons enable row level security;
alter table banners enable row level security;
alter table admin_audit_log enable row level security;
alter table password_recovery_tokens enable row level security;

-- ============================================================
-- SECURITY DEFINER function to check role (avoids recursion)
-- ============================================================
create or replace function public.get_user_role()
returns text language sql security definer stable as $$
  select role from public.profiles where id = auth.uid();
$$;
grant execute on function public.get_user_role() to authenticated;
grant execute on function public.get_user_role() to anon;

-- Products: public read, admin write
create policy "Products are viewable by everyone" on products for select using (is_active = true);
create policy "Products admin manage" on products for all using (
  public.get_user_role() in ('super_admin','admin','product_manager')
);

-- Categories: public read, admin write
create policy "Categories viewable by everyone" on categories for select using (is_active = true);
create policy "Categories admin manage" on categories for all using (
  public.get_user_role() in ('super_admin','admin','product_manager')
);

-- Product Images: public read
create policy "Product images viewable by everyone" on product_images for select using (true);
create policy "Product images admin manage" on product_images for all using (
  public.get_user_role() in ('super_admin','admin','product_manager')
);

-- Product Variants
create policy "Variants viewable by everyone" on product_variants for select using (is_active = true);
create policy "Variants admin manage" on product_variants for all using (
  public.get_user_role() in ('super_admin','admin','product_manager')
);

-- Profiles: users can read/update own, admins can read all
create policy "Users view own profile" on profiles for select using (id = auth.uid());
create policy "Users update own profile" on profiles for update using (id = auth.uid());
create policy "Admins view all profiles" on profiles for select using (
  public.get_user_role() in ('super_admin','admin','support_manager')
);
create policy "Admins update all profiles" on profiles for update using (
  public.get_user_role() in ('super_admin','admin')
);
create policy "Admin can insert profiles" on profiles for insert with check (
  public.get_user_role() in ('super_admin','admin')
);

-- Carts
create policy "Users manage own cart" on carts for all using (user_id = auth.uid());
create policy "Guest carts" on carts for all using (user_id is null);

-- Cart Items
create policy "Users manage own cart items" on cart_items for all using (
  exists (select 1 from carts where id = cart_id and user_id = auth.uid())
);

-- Wishlists
create policy "Users manage own wishlist" on wishlists for all using (user_id = auth.uid());

-- Orders: users see own, admins see all
create policy "Users view own orders" on orders for select using (user_id = auth.uid());
create policy "Users create orders" on orders for insert with check (user_id = auth.uid());
create policy "Admins manage orders" on orders for all using (
  public.get_user_role() in ('super_admin','admin','order_manager')
);

-- Order Items
create policy "Users view own order items" on order_items for select using (
  exists (select 1 from orders where id = order_id and user_id = auth.uid())
);
create policy "Admin manage order items" on order_items for all using (
  public.get_user_role() in ('super_admin','admin','order_manager')
);

-- Payments
create policy "Users view own payments" on payments for select using (
  exists (select 1 from orders where id = order_id and user_id = auth.uid())
);
create policy "Admin manage payments" on payments for all using (
  public.get_user_role() in ('super_admin','admin','order_manager')
);

-- Refunds
create policy "Users view own refunds" on refunds for select using (requested_by = auth.uid());
create policy "Users create refund requests" on refunds for insert with check (requested_by = auth.uid());
create policy "Admin manage refunds" on refunds for all using (
  public.get_user_role() in ('super_admin','admin','order_manager')
);

-- Reviews: public read, users manage own
create policy "Reviews viewable by everyone" on reviews for select using (is_approved = true);
create policy "Users manage own reviews" on reviews for all using (user_id = auth.uid());
create policy "Admin manage reviews" on reviews for all using (
  public.get_user_role() in ('super_admin','admin','support_manager')
);

-- Notifications: users see own
create policy "Users view own notifications" on notifications for select using (user_id = auth.uid());
create policy "System create notifications" on notifications for insert with check (true);
create policy "Users update own notifications" on notifications for update using (user_id = auth.uid());

-- User Activity: users see own, admins see all
create policy "Users view own activity" on user_activity for select using (user_id = auth.uid());
create policy "System create activity" on user_activity for insert with check (true);
create policy "Admin view all activity" on user_activity for select using (
  public.get_user_role() in ('super_admin','admin')
);

-- Languages: public read
create policy "Languages viewable by everyone" on languages for select using (is_active = true);
create policy "Admin manage languages" on languages for all using (
  public.get_user_role() in ('super_admin','admin')
);

-- Translations: public read
create policy "Translations viewable by everyone" on translations for select using (true);
create policy "Admin manage translations" on translations for all using (
  public.get_user_role() in ('super_admin','admin','content_manager')
);

-- Website Settings: public read for public settings
create policy "Public settings viewable" on website_settings for select using (is_public = true);
create policy "Admin manage settings" on website_settings for all using (
  public.get_user_role() in ('super_admin','admin')
);

-- Menu Items: public read
create policy "Menu viewable by everyone" on menu_items for select using (is_active = true);
create policy "Admin manage menu" on menu_items for all using (
  public.get_user_role() in ('super_admin','admin','content_manager')
);

-- Social Links: public read
create policy "Social links viewable by everyone" on social_links for select using (is_active = true);
create policy "Admin manage social links" on social_links for all using (
  public.get_user_role() in ('super_admin','admin','content_manager')
);

-- Coupons
create policy "Coupons viewable by everyone" on coupons for select using (is_active = true);
create policy "Admin manage coupons" on coupons for all using (
  public.get_user_role() in ('super_admin','admin','order_manager')
);

-- Banners: public read
create policy "Banners viewable by everyone" on banners for select using (is_active = true);
create policy "Admin manage banners" on banners for all using (
  public.get_user_role() in ('super_admin','admin','content_manager')
);

-- Contact Submissions, Newsletter Subscribers, and Content Pages policies
-- are defined in migration.sql (run AFTER schema.sql)

-- Admin Audit Log
create policy "Admin view audit log" on admin_audit_log for select using (
  public.get_user_role() in ('super_admin','admin')
);
create policy "System create audit log" on admin_audit_log for insert with check (true);

-- Password Recovery Tokens
create policy "Users manage own tokens" on password_recovery_tokens for all using (user_id = auth.uid());
create policy "Admin manage password recovery" on password_recovery_tokens for all using (
  public.get_user_role() in ('super_admin','admin')
);
