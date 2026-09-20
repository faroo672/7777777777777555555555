-- ============================================================
-- MIGRATION: Contact, Newsletter, Storage, Admin improvements
-- Run this AFTER the initial schema.sql
-- Requires: get_user_role() SECURITY DEFINER function
--           (created by schema.sql or fix-rls.sql)
-- ============================================================

-- ============================================================
-- 1. CONTACT SUBMISSIONS
-- ============================================================
create table if not exists contact_submissions (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  email text not null,
  phone text,
  subject text not null,
  message text not null,
  status text default 'new' check (status in ('new','read','replied','archived')),
  admin_notes text,
  created_at timestamptz default now()
);

alter table contact_submissions enable row level security;

create policy "Anyone can submit contact form" on contact_submissions for insert with check (true);
create policy "Admin manage contact submissions" on contact_submissions for all using (
  public.get_user_role() in ('super_admin','admin','support_manager')
);

-- ============================================================
-- 2. NEWSLETTER SUBSCRIBERS
-- ============================================================
create table if not exists newsletter_subscribers (
  id uuid primary key default uuid_generate_v4(),
  email text unique not null,
  is_active boolean default true,
  unsubscribed_at timestamptz,
  created_at timestamptz default now()
);

alter table newsletter_subscribers enable row level security;

create policy "Anyone can subscribe" on newsletter_subscribers for insert with check (true);
create policy "Admin manage subscribers" on newsletter_subscribers for all using (
  public.get_user_role() in ('super_admin','admin')
);

-- ============================================================
-- 3. CONTENT PAGES (dynamic from database)
-- ============================================================
create table if not exists content_pages (
  id uuid primary key default uuid_generate_v4(),
  slug text unique not null,
  title text not null,
  content text,
  meta_title text,
  meta_description text,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table content_pages enable row level security;

create policy "Content pages viewable by everyone" on content_pages for select using (is_active = true);
create policy "Admin manage content pages" on content_pages for all using (
  public.get_user_role() in ('super_admin','admin','content_manager')
);

-- Default content pages
insert into content_pages (slug, title, content) values
('about', 'About Samee Perfume', '<h2>The Art of Fragrance</h2><p>Welcome to Samee Perfume, your destination for premium perfumes and attars. We believe that fragrance is more than just a scent — it is an expression of your personality, a memory in the making, and an art form that transcends time.</p><p>Founded with a passion for fine fragrances, Samee Perfume curates the finest collection of premium perfumes, traditional attars, and modern fragrances from around the world.</p>'),
('terms', 'Terms & Conditions', '<p><strong>Last updated:</strong> January 2025</p><h2>General Terms</h2><p>By accessing and using the Samee Perfume website, you agree to be bound by these Terms and Conditions.</p><h2>Products and Pricing</h2><p>All product descriptions, images, and prices are subject to change without notice.</p>'),
('privacy', 'Privacy Policy', '<p><strong>Last updated:</strong> January 2025</p><h2>Information We Collect</h2><p>We collect information you provide directly to us, such as when you create an account, make a purchase, or contact us.</p>'),
('shipping', 'Shipping Policy', '<h2>Delivery Areas</h2><p>We deliver across Pakistan. Standard delivery takes 3-5 business days.</p><h2>Shipping Fees</h2><p>Free shipping on orders over Rs 5,000. Standard shipping fee is Rs 250.</p>'),
('returns', 'Return Policy', '<h2>Return Window</h2><p>You may return items within 7 days of delivery for a full refund.</p><h2>Conditions</h2><p>Items must be unused and in original packaging.</p>'),
('refund', 'Refund Policy', '<h2>Refund Processing</h2><p>Refunds are processed within 5-7 business days after we receive the returned item.</p>')
on conflict (slug) do nothing;

-- ============================================================
-- 4. STORAGE BUCKETS for product images & banners
-- ============================================================
-- Note: Create these buckets manually in Supabase Dashboard > Storage
-- Bucket name: product-images  (public: true)
-- Bucket name: banners         (public: true)
-- Bucket name: avatars         (public: true)
--
-- Or run these via Supabase CLI / Dashboard:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('product-images', 'product-images', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('banners', 'banners', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);

-- Storage RLS policies
create policy "Product images public access" on storage.objects for select using (bucket_id = 'product-images');
create policy "Product images admin upload" on storage.objects for insert with check (
  bucket_id = 'product-images' and public.get_user_role() in ('super_admin','admin','product_manager')
);
create policy "Product images admin delete" on storage.objects for delete using (
  bucket_id = 'product-images' and public.get_user_role() in ('super_admin','admin','product_manager')
);

create policy "Banners public access" on storage.objects for select using (bucket_id = 'banners');
create policy "Banners admin upload" on storage.objects for insert with check (
  bucket_id = 'banners' and public.get_user_role() in ('super_admin','admin','content_manager')
);
create policy "Banners admin delete" on storage.objects for delete using (
  bucket_id = 'banners' and public.get_user_role() in ('super_admin','admin','content_manager')
);

create policy "Avatars public access" on storage.objects for select using (bucket_id = 'avatars');
create policy "Avatars user upload" on storage.objects for insert with check (
  bucket_id = 'avatars' and auth.uid() is not null
);

-- ============================================================
-- 5. NOTIFICATIONS: add admin delete policy
-- ============================================================
create policy "Admin delete notifications" on notifications for delete using (
  public.get_user_role() in ('super_admin','admin')
);

-- ============================================================
-- 6. PROFILES: allow admin insert (for creating admin users)
-- ============================================================
create policy "Admin can insert profiles" on profiles for insert with check (
  public.get_user_role() in ('super_admin','admin')
);

-- ============================================================
-- Done! Run this SQL in Supabase SQL Editor after schema.sql
-- ============================================================
