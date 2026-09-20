-- ============================================================
-- FIX: RLS policies - Complete Rewrite
-- 
-- PROBLEM: The original schema.sql had infinite recursion on 
-- profiles (admin policy queried profiles from within profiles).
-- The previous "fix" used auth.jwt() ->> 'role' but Supabase 
-- JWT role claim is always 'authenticated' — never contains 
-- custom app roles. This blocks ALL admin writes and breaks 
-- public reads too.
--
-- SOLUTION: Create a SECURITY DEFINER function that reads the 
-- role from profiles table (bypasses RLS recursion), then use 
-- it in all admin policies.
--
-- RUN THIS ENTIRE SCRIPT in Supabase SQL Editor.
-- ============================================================

-- 0. CREATE TABLES IF NOT EXISTS (needed before policies)
CREATE TABLE IF NOT EXISTS contact_submissions (
  id uuid primary key default uuid_generate_v4(),
  name text not null, email text not null, phone text,
  subject text not null, message text not null,
  status text default 'new' check (status in ('new','read','replied','archived')),
  admin_notes text, created_at timestamptz default now()
);
ALTER TABLE contact_submissions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS newsletter_subscribers (
  id uuid primary key default uuid_generate_v4(),
  email text unique not null, is_active boolean default true,
  unsubscribed_at timestamptz, created_at timestamptz default now()
);
ALTER TABLE newsletter_subscribers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS content_pages (
  id uuid primary key default uuid_generate_v4(),
  slug text unique not null, title text not null, content text,
  meta_title text, meta_description text, is_active boolean default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
ALTER TABLE content_pages ENABLE ROW LEVEL SECURITY;

-- 1. Create helper function to read role (SECURITY DEFINER bypasses RLS)
create or replace function public.get_user_role()
returns text
language sql
security definer
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Grant execute
grant execute on function public.get_user_role() to authenticated;
grant execute on function public.get_user_role() to anon;

-- ============================================================
-- 2. DROP ALL existing policies on every affected table
-- ============================================================

-- Products
drop policy if exists "Products are viewable by everyone" on products;
drop policy if exists "Products admin manage" on products;

-- Categories
drop policy if exists "Categories viewable by everyone" on categories;
drop policy if exists "Categories admin manage" on categories;

-- Product images
drop policy if exists "Product images viewable by everyone" on product_images;
drop policy if exists "Product images admin manage" on product_images;
drop policy if exists "Product images public access" on product_images;

-- Product variants
drop policy if exists "Variants viewable by everyone" on product_variants;
drop policy if exists "Variants admin manage" on product_variants;

-- Profiles
drop policy if exists "Users view own profile" on profiles;
drop policy if exists "Users update own profile" on profiles;
drop policy if exists "Admins view all profiles" on profiles;
drop policy if exists "Admins update all profiles" on profiles;
drop policy if exists "Admin can insert profiles" on profiles;

-- Carts
drop policy if exists "Users manage own cart" on carts;
drop policy if exists "Guest carts" on carts;
drop policy if exists "Users manage own cart items" on cart_items;
drop policy if exists "Guest cart items" on cart_items;

-- Wishlists
drop policy if exists "Users manage own wishlist" on wishlists;

-- Orders
drop policy if exists "Users view own orders" on orders;
drop policy if exists "Users create orders" on orders;
drop policy if exists "Admins manage orders" on orders;

-- Order items
drop policy if exists "Users view own order items" on order_items;
drop policy if exists "Admin manage order items" on order_items;

-- Payments
drop policy if exists "Users view own payments" on payments;
drop policy if exists "Admin manage payments" on payments;

-- Refunds
drop policy if exists "Users view own refunds" on refunds;
drop policy if exists "Users create refund requests" on refunds;
drop policy if exists "Admin manage refunds" on refunds;

-- Reviews
drop policy if exists "Reviews viewable by everyone" on reviews;
drop policy if exists "Users manage own reviews" on reviews;
drop policy if exists "Admin manage reviews" on reviews;

-- Notifications
drop policy if exists "Users view own notifications" on notifications;
drop policy if exists "System create notifications" on notifications;
drop policy if exists "Users update own notifications" on notifications;
drop policy if exists "Admin delete notifications" on notifications;

-- User activity
drop policy if exists "Users view own activity" on user_activity;
drop policy if exists "System create activity" on user_activity;
drop policy if exists "Admin view all activity" on user_activity;

-- Languages
drop policy if exists "Languages viewable by everyone" on languages;
drop policy if exists "Admin manage languages" on languages;

-- Translations
drop policy if exists "Translations viewable by everyone" on translations;
drop policy if exists "Admin manage translations" on translations;

-- Website settings
drop policy if exists "Public settings viewable" on website_settings;
drop policy if exists "Admin manage settings" on website_settings;

-- Menu items
drop policy if exists "Menu viewable by everyone" on menu_items;
drop policy if exists "Admin manage menu" on menu_items;

-- Social links
drop policy if exists "Social links viewable by everyone" on social_links;
drop policy if exists "Admin manage social links" on social_links;

-- Coupons
drop policy if exists "Coupons viewable by everyone" on coupons;
drop policy if exists "Admin manage coupons" on coupons;

-- Banners
drop policy if exists "Banners public access" on banners;
drop policy if exists "Banners viewable by everyone" on banners;
drop policy if exists "Admin manage banners" on banners;

-- Contact submissions
drop policy if exists "Anyone can submit contact form" on contact_submissions;
drop policy if exists "Admin manage contact submissions" on contact_submissions;

-- Newsletter
drop policy if exists "Anyone can subscribe" on newsletter_subscribers;
drop policy if exists "Admin manage subscribers" on newsletter_subscribers;

-- Content pages
drop policy if exists "Content pages viewable by everyone" on content_pages;
drop policy if exists "Admin manage content pages" on content_pages;

-- Admin audit log
drop policy if exists "Admin view audit log" on admin_audit_log;
drop policy if exists "System create audit log" on admin_audit_log;
drop policy if exists "Admin manage audit log" on admin_audit_log;

-- Password recovery
drop policy if exists "Users manage own tokens" on password_recovery_tokens;
drop policy if exists "Admin manage password recovery" on password_recovery_tokens;

-- ============================================================
-- 3. RECREATE all policies using get_user_role()
-- ============================================================

-- PRODUCTS
create policy "Products are viewable by everyone" on products
  for select using (is_active = true);
create policy "Products admin manage" on products
  for all using (public.get_user_role() in ('super_admin', 'admin', 'product_manager'));

-- CATEGORIES
create policy "Categories viewable by everyone" on categories
  for select using (is_active = true);
create policy "Categories admin manage" on categories
  for all using (public.get_user_role() in ('super_admin', 'admin', 'product_manager'));

-- PRODUCT IMAGES
create policy "Product images public access" on product_images
  for select using (true);
create policy "Product images admin manage" on product_images
  for all using (public.get_user_role() in ('super_admin', 'admin', 'product_manager'));

-- PRODUCT VARIANTS
create policy "Variants viewable by everyone" on product_variants
  for select using (is_active = true);
create policy "Variants admin manage" on product_variants
  for all using (public.get_user_role() in ('super_admin', 'admin', 'product_manager'));

-- PROFILES (no recursion!)
create policy "Users view own profile" on profiles
  for select using (id = auth.uid());
create policy "Users update own profile" on profiles
  for update using (id = auth.uid());
create policy "Admins view all profiles" on profiles
  for select using (public.get_user_role() in ('super_admin', 'admin', 'support_manager'));
create policy "Admins update all profiles" on profiles
  for update using (public.get_user_role() in ('super_admin', 'admin'));
create policy "Admin can insert profiles" on profiles
  for insert with check (public.get_user_role() in ('super_admin', 'admin'));

-- CARTS
create policy "Users manage own cart" on carts
  for all using (user_id = auth.uid());
create policy "Guest carts" on carts
  for all using (user_id is null);

-- CART ITEMS
create policy "Users manage own cart items" on cart_items
  for all using (exists (select 1 from carts where id = cart_id and user_id = auth.uid()));
create policy "Guest cart items" on cart_items
  for all using (exists (select 1 from carts where id = cart_id and user_id IS NULL));

-- WISHLISTS
create policy "Users manage own wishlist" on wishlists
  for all using (user_id = auth.uid());

-- ORDERS
create policy "Users view own orders" on orders
  for select using (user_id = auth.uid());
create policy "Users create orders" on orders
  for insert with check (user_id = auth.uid());
create policy "Admins manage orders" on orders
  for all using (public.get_user_role() in ('super_admin', 'admin', 'order_manager'));

-- ORDER ITEMS
create policy "Users view own order items" on order_items
  for select using (exists (select 1 from orders where id = order_id and user_id = auth.uid()));
create policy "Admin manage order items" on order_items
  for all using (public.get_user_role() in ('super_admin', 'admin', 'order_manager'));

-- PAYMENTS
create policy "Users view own payments" on payments
  for select using (exists (select 1 from orders where id = order_id and orders.user_id = auth.uid()));
create policy "Admin manage payments" on payments
  for all using (public.get_user_role() in ('super_admin', 'admin', 'order_manager'));

-- REFUNDS
create policy "Users view own refunds" on refunds
  for select using (requested_by = auth.uid());
create policy "Users create refund requests" on refunds
  for insert with check (requested_by = auth.uid());
create policy "Admin manage refunds" on refunds
  for all using (public.get_user_role() in ('super_admin', 'admin', 'order_manager'));

-- REVIEWS
create policy "Reviews viewable by everyone" on reviews
  for select using (is_approved = true);
create policy "Users manage own reviews" on reviews
  for all using (user_id = auth.uid());
create policy "Admin manage reviews" on reviews
  for all using (public.get_user_role() in ('super_admin', 'admin', 'support_manager'));

-- NOTIFICATIONS
create policy "Users view own notifications" on notifications
  for select using (user_id = auth.uid());
create policy "System create notifications" on notifications
  for insert with check (true);
create policy "Users update own notifications" on notifications
  for update using (user_id = auth.uid());
create policy "Admin delete notifications" on notifications
  for delete using (public.get_user_role() in ('super_admin', 'admin'));

-- USER ACTIVITY
create policy "Users view own activity" on user_activity
  for select using (user_id = auth.uid());
create policy "System create activity" on user_activity
  for insert with check (true);
create policy "Admin view all activity" on user_activity
  for select using (public.get_user_role() in ('super_admin', 'admin'));

-- LANGUAGES
create policy "Languages viewable by everyone" on languages
  for select using (is_active = true);
create policy "Admin manage languages" on languages
  for all using (public.get_user_role() in ('super_admin', 'admin'));

-- TRANSLATIONS
create policy "Translations viewable by everyone" on translations
  for select using (true);
create policy "Admin manage translations" on translations
  for all using (public.get_user_role() in ('super_admin', 'admin', 'content_manager'));

-- WEBSITE SETTINGS
create policy "Public settings viewable" on website_settings
  for select using (is_public = true);
create policy "Admin manage settings" on website_settings
  for all using (public.get_user_role() in ('super_admin', 'admin'));

-- MENU ITEMS
create policy "Menu viewable by everyone" on menu_items
  for select using (is_active = true);
create policy "Admin manage menu" on menu_items
  for all using (public.get_user_role() in ('super_admin', 'admin', 'content_manager'));

-- SOCIAL LINKS
create policy "Social links viewable by everyone" on social_links
  for select using (is_active = true);
create policy "Admin manage social links" on social_links
  for all using (public.get_user_role() in ('super_admin', 'admin', 'content_manager'));

-- COUPONS
create policy "Coupons viewable by everyone" on coupons
  for select using (is_active = true);
create policy "Admin manage coupons" on coupons
  for all using (public.get_user_role() in ('super_admin', 'admin', 'order_manager'));

-- BANNERS
create policy "Banners viewable by everyone" on banners
  for select using (true);
create policy "Admin manage banners" on banners
  for all using (public.get_user_role() in ('super_admin', 'admin', 'content_manager'));

-- CONTACT SUBMISSIONS
create policy "Anyone can submit contact form" on contact_submissions
  for insert with check (true);
create policy "Admin manage contact submissions" on contact_submissions
  for all using (public.get_user_role() in ('super_admin', 'admin', 'support_manager'));

-- NEWSLETTER
create policy "Anyone can subscribe" on newsletter_subscribers
  for insert with check (true);
create policy "Admin manage subscribers" on newsletter_subscribers
  for all using (public.get_user_role() in ('super_admin', 'admin'));

-- CONTENT PAGES
create policy "Content pages viewable by everyone" on content_pages
  for select using (is_active = true);
create policy "Admin manage content pages" on content_pages
  for all using (public.get_user_role() in ('super_admin', 'admin', 'content_manager'));

-- ADMIN AUDIT LOG
create policy "System create audit log" on admin_audit_log
  for insert with check (true);
create policy "Admin manage audit log" on admin_audit_log
  for all using (public.get_user_role() in ('super_admin', 'admin'));

-- PASSWORD RECOVERY
create policy "Users manage own tokens" on password_recovery_tokens
  for all using (user_id = auth.uid());
create policy "Admin manage password recovery" on password_recovery_tokens
  for all using (public.get_user_role() in ('super_admin', 'admin'));

-- ============================================================
-- 4. STORAGE BUCKETS (idempotent — safe to run multiple times)
-- ============================================================
INSERT INTO storage.buckets (id, name, public) VALUES ('product-images', 'product-images', true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('banners', 'banners', true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 5. STORAGE RLS POLICIES (drop + recreate for idempotency)
-- ============================================================

-- Product images storage
DROP POLICY IF EXISTS "Product images public access" ON storage.objects;
DROP POLICY IF EXISTS "Product images admin upload" ON storage.objects;
DROP POLICY IF EXISTS "Product images admin delete" ON storage.objects;

CREATE POLICY "Product images public access" ON storage.objects
  FOR SELECT USING (bucket_id = 'product-images');
CREATE POLICY "Product images admin upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'product-images' AND public.get_user_role() IN ('super_admin', 'admin', 'product_manager')
  );
CREATE POLICY "Product images admin delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'product-images' AND public.get_user_role() IN ('super_admin', 'admin', 'product_manager')
  );

-- Banners storage
DROP POLICY IF EXISTS "Banners public access" ON storage.objects;
DROP POLICY IF EXISTS "Banners admin upload" ON storage.objects;
DROP POLICY IF EXISTS "Banners admin delete" ON storage.objects;

CREATE POLICY "Banners public access" ON storage.objects
  FOR SELECT USING (bucket_id = 'banners');
CREATE POLICY "Banners admin upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'banners' AND public.get_user_role() IN ('super_admin', 'admin', 'content_manager')
  );
CREATE POLICY "Banners admin delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'banners' AND public.get_user_role() IN ('super_admin', 'admin', 'content_manager')
  );

-- Avatars storage
DROP POLICY IF EXISTS "Avatars public access" ON storage.objects;
DROP POLICY IF EXISTS "Avatars user upload" ON storage.objects;

CREATE POLICY "Avatars public access" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Avatars user upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.uid() IS NOT NULL);

-- ============================================================
-- 6. SEED DATA (idempotent — ON CONFLICT prevents duplicates)
-- ============================================================

-- Languages
INSERT INTO languages (code, name, native_name, is_rtl, is_active, sort_order) VALUES
('en', 'English', 'English', false, true, 1),
('ur', 'Urdu', 'اردو', true, true, 2),
('ar', 'Arabic', 'العربية', true, true, 3),
('ps', 'Pashto', 'پښتو', true, true, 4),
('sd', 'Sindhi', 'سنڌي', true, true, 5),
('pa', 'Punjabi', 'ਪੰਜਾਬੀ', false, true, 6),
('skr', 'Saraiki', 'سرائیکی', false, true, 7),
('khw', 'Khowar', 'کھوار', false, true, 8),
('bal', 'Balochi', 'بلوچی', true, true, 9),
('fa', 'Persian', 'فارسی', true, true, 10)
ON CONFLICT (code) DO NOTHING;

-- Website Settings
INSERT INTO website_settings (key, value, category, is_public) VALUES
('site_name', '"Samee Perfume"', 'general', true),
('site_tagline', '"Premium Perfumes & Attars"', 'general', true),
('default_currency', '"PKR"', 'general', true),
('currency_symbol', '"Rs"', 'general', true),
('support_email', '"support@sameeperfume.com"', 'contact', true),
('support_phone', '"+92 300 1234567"', 'contact', true),
('whatsapp_number', '"923001234567"', 'whatsapp', true),
('meta_title', '"Samee Perfume - Premium Perfumes & Attars in Pakistan"', 'seo', true),
('meta_description', '"Shop authentic premium perfumes, attars, and fragrances at Samee Perfume. Free delivery across Pakistan."', 'seo', true),
('facebook_url', '"https://facebook.com/sameeperfume"', 'social', true),
('instagram_url', '"https://instagram.com/sameeperfume"', 'social', true),
('tiktok_url', '"https://tiktok.com/@sameeperfume"', 'social', true),
('youtube_url', '"https://youtube.com/@sameeperfume"', 'social', true),
('twitter_url', '"https://twitter.com/sameeperfume"', 'social', true),
('telegram_url', '"https://t.me/sameeperfume"', 'social', true),
('bank_account_title', '"Samee Perfume LLC"', 'payment', false),
('bank_account_number', '"1234567890"', 'payment', false),
('bank_name', '"HBL - Habib Bank Limited"', 'payment', false),
('bank_iban', '"PK12HABB0012345678901234"', 'payment', false),
('easypaisa_number', '"03001234567"', 'payment', false),
('jazzcash_number', '"03001234567"', 'payment', false),
('shipping_fee', '250', 'shipping', true),
('free_shipping_threshold', '5000', 'shipping', true)
ON CONFLICT (key) DO NOTHING;

-- Content Pages
INSERT INTO content_pages (slug, title, content, meta_title, meta_description, is_active) VALUES
('about', 'About Samee Perfume', '<h2>The Art of Fragrance</h2><p>Welcome to Samee Perfume, your destination for premium perfumes and attars.</p>', 'About Samee Perfume', 'Learn about Samee Perfume.', true),
('terms', 'Terms & Conditions', '<p>By accessing our website you agree to these terms.</p>', 'Terms & Conditions', 'Read our terms.', true),
('privacy', 'Privacy Policy', '<p>We collect information you provide directly.</p>', 'Privacy Policy', 'Read our privacy policy.', true),
('shipping', 'Shipping Policy', '<p>We deliver across Pakistan. Standard delivery takes 3-5 business days.</p>', 'Shipping Policy', 'Learn about shipping.', true),
('returns', 'Return Policy', '<p>You may return items within 7 days of delivery.</p>', 'Return Policy', 'Learn about returns.', true),
('refund', 'Refund Policy', '<p>Refunds are processed within 5-7 business days.</p>', 'Refund Policy', 'Learn about refunds.', true)
ON CONFLICT (slug) DO NOTHING;

-- Categories
INSERT INTO categories (name, slug, description, sort_order, is_active) VALUES
('Premium Perfumes', 'premium-perfumes', 'High-end designer and niche perfumes', 1, true),
('Traditional Attars', 'traditional-attars', 'Classic Arabic and Pakistani attars', 2, true),
('Oud Collection', 'oud-collection', 'Premium oud-based fragrances', 3, true),
('Gift Sets', 'gift-sets', 'Curated fragrance gift collections', 4, true),
('Accessories', 'accessories', 'Perfume accessories and samples', 5, true)
ON CONFLICT (slug) DO NOTHING;

-- Admin Roles
INSERT INTO admin_roles (name, label, permissions) VALUES
('super_admin', 'Super Admin', '["all"]'),
('admin', 'Admin', '["products.read","products.write","orders.read","orders.write","users.read","reviews.read","reviews.write","settings.read","settings.write","content.write"]'),
('product_manager', 'Product Manager', '["products.read","products.write","categories.read","categories.write","inventory.write"]'),
('order_manager', 'Order Manager', '["orders.read","orders.write","refunds.read","refunds.write"]'),
('support_manager', 'Support Manager', '["users.read","reviews.read","reviews.write","orders.read"]'),
('content_manager', 'Content Manager', '["content.write","pages.write","banners.write","settings.read"]')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- DONE! Copy entire file > Supabase Dashboard > SQL Editor > Run
-- ============================================================
