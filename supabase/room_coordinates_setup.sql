-- Create room_coordinates table
create table if not exists public.room_coordinates (
  room_code text primary key,
  lat double precision not null,
  lon double precision not null,
  height double precision default 0.0,
  floor integer default 1,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Enable RLS
alter table public.room_coordinates enable row level security;

-- Policy: Authenticated users can read
create policy "Authenticated users can read room coordinates"
  on public.room_coordinates for select
  using ( auth.role() = 'authenticated' );

-- Policy: Only admins can insert
create policy "Admins can insert room coordinates"
  on public.room_coordinates for insert
  with check (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.is_admin = true
    )
  );

-- Policy: Only admins can update (only rows they created, or all admins)
create policy "Admins can update room coordinates"
  on public.room_coordinates for update
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.is_admin = true
    )
  );

-- Policy: Only admins can delete (only rows they created, or all admins)
create policy "Admins can delete room coordinates"
  on public.room_coordinates for delete
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.is_admin = true
    )
  );

-- Optional: trigger to auto-update updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger handle_room_coordinates_updated_at
  before update on public.room_coordinates
  for each row
  execute procedure public.handle_updated_at();
