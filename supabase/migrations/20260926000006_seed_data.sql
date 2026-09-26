-- ==============================================================================
-- Migration: 20260926000006_seed_data.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: Seed data with sample companies, lines, and stations for testing
-- ==============================================================================

-- 1. Insert Sample Bus Companies
INSERT INTO public.companies (id, name, is_active)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'شركة النقل الجامعي السريع (FastUni Bus)', true),
    ('22222222-2222-2222-2222-222222222222', 'شركة باصات العاصمة (Capital Shuttles)', true)
ON CONFLICT (id) DO NOTHING;

-- 2. Insert Lines for FastUni Bus
INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily, is_active)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'خط مدينة نصر - التجمع - الجامعة', 3500.00, 6500.00, 50.00, true),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'خط المعادي - حلوان - الجامعة', 3800.00, 7000.00, 55.00, true),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'خط الجيزة - المهندسين - الجامعة', 4000.00, 7500.00, 60.00, true)
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Stations for Line A (مدينة نصر - التجمع - الجامعة)
INSERT INTO public.stations (line_id, name, order_index, departure_time, return_time)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة سيتي ستارز - أول عباس', 1, '07:00:00', '16:00:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة مكرم عبيد - تقاطع النصر', 2, '07:15:00', '15:45:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة التجمع الأول - المحور', 3, '07:40:00', '15:20:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة التجمع الخامس - التسعين الشمالي', 4, '08:00:00', '15:00:00')
ON CONFLICT DO NOTHING;

-- 4. Insert Stations for Line B (المعادي - حلوان - الجامعة)
INSERT INTO public.stations (line_id, name, order_index, departure_time, return_time)
VALUES
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'محطة مترو حلوان', 1, '06:45:00', '16:15:00'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'محطة المعادي - شارع النصر', 2, '07:15:00', '15:45:00'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'محطة زهراء المعادي - كارفور', 3, '07:35:00', '15:25:00')
ON CONFLICT DO NOTHING;

-- 5. Insert Stations for Line C (الجيزة - المهندسين - الجامعة)
INSERT INTO public.stations (line_id, name, order_index, departure_time, return_time)
VALUES
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'محطة ميدان لبنان - المهندسين', 1, '07:00:00', '16:00:00'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'محطة ميدان الجيزة - شارع الجامعة', 2, '07:25:00', '15:35:00'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'محطة الرماية - طريق الهرم', 3, '07:45:00', '15:15:00')
ON CONFLICT DO NOTHING;
